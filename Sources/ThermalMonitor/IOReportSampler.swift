import CSensors
import Foundation

/// One DVFS cluster (a group of cores, or the GPU) as reported by IOReport.
struct ClusterLoad {
    var name: String
    /// Fraction of the interval the cluster spent out of idle, 0...1.
    var activeResidency: Double
    /// Residency in each non-idle DVFS state, lowest frequency first.
    var stateResidencies: [Double]
    /// Average frequency in GHz while active, if the DVFS table could be resolved.
    var averageGHz: Double?
}

struct PowerSample {
    var cpuWatts: Double?
    var gpuWatts: Double?
    var aneWatts: Double?
    var dramWatts: Double?

    /// What the SoC package is drawing, as far as the energy counters can see.
    var totalWatts: Double? {
        let parts = [cpuWatts, gpuWatts, aneWatts, dramWatts].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}

struct IOReportSample {
    var power = PowerSample()
    var cpuClusters: [ClusterLoad] = []
    var gpu: ClusterLoad?
}

/// Reads energy counters and DVFS residencies out of IOReport.
///
/// IOReport counters are monotonic, so every reading is the difference between two
/// snapshots. The sampler holds onto the previous snapshot and reports the delta.
final class IOReportSampler {
    private var handle: UnsafeMutableRawPointer?
    private var previous: CFDictionary?
    private var previousTime: CFAbsoluteTime = 0
    private var clocks = ClockTables()

    var isAvailable: Bool { handle != nil }

    init() {
        handle = iorep_subscribe()
        if handle != nil {
            previous = iorep_sample(handle)
            previousTime = CFAbsoluteTimeGetCurrent()
        }
    }

    deinit {
        if let handle { iorep_release(handle) }
    }

    /// Returns nil until a second snapshot is available to difference against.
    func sample() -> IOReportSample? {
        guard let handle, let previous else { return nil }
        guard let current = iorep_sample(handle) else { return nil }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - previousTime
        defer {
            self.previous = current
            self.previousTime = now
        }

        guard let delta = iorep_delta(previous, current), elapsed > 0 else { return nil }
        return parse(delta: delta, elapsed: elapsed)
    }

    private func parse(delta: CFDictionary, elapsed: Double) -> IOReportSample {
        var result = IOReportSample()
        var cpuCores: [(cluster: String, load: RawResidency)] = []
        var gpuRaw: RawResidency?

        guard let channels = iorep_channels(delta) else { return result }
        for index in 0..<CFArrayGetCount(channels) {
            guard let raw = CFArrayGetValueAtIndex(channels, index) else { continue }
            let channel = unsafeBitCast(raw, to: CFDictionary.self)
            guard let group = string(iorep_channel_group(channel)),
                  let name = string(iorep_channel_name(channel)) else { continue }

            switch group {
            case "Energy Model":
                let joules = Double(iorep_simple_value(channel)) * energyScale(of: channel)
                guard joules > 0 else { continue }
                let watts = joules / elapsed
                switch name {
                case "CPU Energy": result.power.cpuWatts = watts
                case "GPU Energy": result.power.gpuWatts = watts
                case "DRAM":       result.power.dramWatts = watts
                case let n where n.hasPrefix("ANE"): result.power.aneWatts = watts
                default: break
                }

            case "CPU Stats":
                guard let residency = RawResidency(channel: channel) else { continue }
                cpuCores.append((cluster: clusterName(forCore: name), load: residency))

            case "GPU Stats":
                gpuRaw = RawResidency(channel: channel)

            default:
                break
            }
        }

        result.cpuClusters = collapse(cores: cpuCores)
        if let gpuRaw {
            result.gpu = ClusterLoad(name: "GPU",
                                     activeResidency: gpuRaw.activeFraction,
                                     stateResidencies: gpuRaw.normalizedStates,
                                     averageGHz: clocks.averageGHz(for: .gpu, states: gpuRaw.states))
        }
        return result
    }

    /// IOReport channels come back as one row per core. Cores in the same cluster are
    /// averaged together so the UI shows "Efficiency"/"Performance" rather than 18 rows.
    private func collapse(cores: [(cluster: String, load: RawResidency)]) -> [ClusterLoad] {
        var order: [String] = []
        var grouped: [String: [RawResidency]] = [:]
        for core in cores {
            if grouped[core.cluster] == nil { order.append(core.cluster) }
            grouped[core.cluster, default: []].append(core.load)
        }

        return order.compactMap { name in
            guard let members = grouped[name], !members.isEmpty else { return nil }
            let summed = members.dropFirst().reduce(members[0]) { $0.adding($1) }
            let kind: ClockTables.Domain = name == "Efficiency" ? .efficiency : .performance
            return ClusterLoad(name: name,
                               activeResidency: summed.activeFraction,
                               stateResidencies: summed.normalizedStates,
                               averageGHz: clocks.averageGHz(for: kind, states: summed.states))
        }
    }

    /// Apple names efficiency cores ECPU/MCPU and performance cores PCPU, optionally
    /// with a cluster index (`MCPU10` is core 0 of the second efficiency cluster).
    private func clusterName(forCore name: String) -> String {
        if name.hasPrefix("P") { return "Performance" }
        if name.hasPrefix("E") || name.hasPrefix("M") { return "Efficiency" }
        return name
    }

    private func energyScale(of channel: CFDictionary) -> Double {
        switch string(iorep_channel_unit(channel))?.lowercased() {
        case "nj": return 1e-9
        case "uj": return 1e-6
        case "mj": return 1e-3
        case "j":  return 1
        default:   return 0
        }
    }

    private func string(_ value: CFString?) -> String? {
        value.map { $0 as String }
    }
}

/// Residency ticks for one channel, split into idle and per-DVFS-state buckets.
private struct RawResidency {
    var idle: Double
    /// Ticks per active DVFS state, ordered lowest frequency first.
    var states: [Double]

    /// Channels report a leading `DOWN` and `IDLE` bucket (power-gated and clock-gated
    /// respectively); everything after those is a real frequency step.
    init?(channel: CFDictionary) {
        let count = iorep_state_count(channel)
        guard count > 0 else { return nil }

        var idle = 0.0
        var states: [Double] = []
        for index in 0..<count {
            let ticks = Double(iorep_state_residency(channel, index))
            let name = (iorep_state_name(channel, index) as String?) ?? ""
            if name == "DOWN" || name == "IDLE" || name == "OFF" {
                idle += ticks
            } else {
                states.append(ticks)
            }
        }
        guard !states.isEmpty else { return nil }
        self.idle = idle
        self.states = states
    }

    private init(idle: Double, states: [Double]) {
        self.idle = idle
        self.states = states
    }

    func adding(_ other: RawResidency) -> RawResidency {
        guard states.count == other.states.count else { return self }
        return RawResidency(idle: idle + other.idle,
                            states: zip(states, other.states).map(+))
    }

    var total: Double { idle + states.reduce(0, +) }

    var activeFraction: Double {
        let total = self.total
        return total > 0 ? states.reduce(0, +) / total : 0
    }

    /// Per-state share of the whole interval, so the bars sum to `activeFraction`.
    var normalizedStates: [Double] {
        let total = self.total
        return total > 0 ? states.map { $0 / total } : states.map { _ in 0 }
    }
}
