import CSensors
import Foundation

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
    var gpu: ClusterLoad?
}

/// Reads energy counters and GPU residency out of IOReport.
///
/// IOReport counters are monotonic, so every reading is the difference between two
/// snapshots. The sampler holds onto the previous snapshot and reports the delta.
final class IOReportSampler {
    private var handle: UnsafeMutableRawPointer?
    private var previous: CFDictionary?
    private var previousTime: CFAbsoluteTime = 0

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

            case "GPU Stats":
                if let residency = GPUResidency(channel: channel) {
                    result.gpu = ClusterLoad(name: "GPU", activeResidency: residency.activeFraction)
                }

            default:
                break
            }
        }
        return result
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

/// GPU performance-state residency, split into powered-down and clocked buckets.
///
/// Unlike the CPU core channels this one is trustworthy: the `OFF` bucket tracks GPU
/// energy draw closely (~5% active at 0.06 W, ~58% at 1.9 W on an M5 Max).
private struct GPUResidency {
    var idle: Double
    var active: Double

    init?(channel: CFDictionary) {
        let count = iorep_state_count(channel)
        guard count > 0 else { return nil }

        var idle = 0.0
        var active = 0.0
        for index in 0..<count {
            let ticks = Double(iorep_state_residency(channel, index))
            switch (iorep_state_name(channel, index) as String?) ?? "" {
            case "OFF", "DOWN", "IDLE": idle += ticks
            default: active += ticks
            }
        }
        guard idle + active > 0 else { return nil }
        self.idle = idle
        self.active = active
    }

    var activeFraction: Double { active / (idle + active) }
}
