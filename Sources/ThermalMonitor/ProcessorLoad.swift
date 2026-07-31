import Darwin
import Foundation

/// How busy one group of cores (a CPU performance tier, or the GPU) was over an interval.
struct ClusterLoad {
    var name: String
    /// Fraction of the interval spent out of idle, 0...1.
    var activeResidency: Double
}

/// Per-performance-tier CPU utilization, from the same Mach tick counters `top` reads.
///
/// IOReport also publishes CPU performance-state residencies, and they look like the
/// natural source next to the power counters — but on some SoCs the per-core channels
/// report the cluster's shared DVFS state replicated across every core, with no idle
/// accounting at all. On an M5 Max all six `PCPU*` channels return byte-identical
/// residency with `IDLE=0` whether the machine is idle or saturated, which reads as a
/// permanent 100%. The Mach counters are public API and correct everywhere.
final class ProcessorLoad {
    private let tiers: [(name: String, cpus: Range<Int>)]
    private var previous: [CPUTicks]

    init() {
        tiers = Self.readTiers()
        previous = Self.sample()
    }

    /// Utilization since the previous call. Empty until two samples exist.
    func read() -> [ClusterLoad] {
        let current = Self.sample()
        defer { previous = current }
        guard !current.isEmpty, current.count == previous.count else { return [] }

        return tiers.compactMap { tier in
            guard tier.cpus.upperBound <= current.count else { return nil }
            var active = 0.0
            var total = 0.0
            for cpu in tier.cpus {
                active += current[cpu].active - previous[cpu].active
                total += current[cpu].total - previous[cpu].total
            }
            guard total > 0 else { return nil }
            return ClusterLoad(name: tier.name, activeResidency: active / total)
        }
    }

    // MARK: - Topology

    /// Apple Silicon numbers logical CPUs starting with the *least* performant tier, so
    /// the perf levels are walked back to front to lay out the index ranges. The tier
    /// names come from the kernel rather than being hardcoded, because they differ per
    /// generation — "Efficiency"/"Performance" on M1-M4, "Performance"/"Super" on M5.
    private static func readTiers() -> [(name: String, cpus: Range<Int>)] {
        let cpuCount = sysctlInt("hw.logicalcpu") ?? 0
        let levels = sysctlInt("hw.nperflevels") ?? 0
        guard cpuCount > 0 else { return [] }
        guard levels > 1 else { return [(name: "CPU", cpus: 0..<cpuCount)] }

        var tiers: [(name: String, cpus: Range<Int>)] = []
        var next = 0
        for level in stride(from: levels - 1, through: 0, by: -1) {
            let count = sysctlInt("hw.perflevel\(level).logicalcpu") ?? 0
            guard count > 0, next + count <= cpuCount else { continue }
            let name = sysctlString("hw.perflevel\(level).name") ?? "CPU \(level)"
            tiers.append((name: name, cpus: next..<(next + count)))
            next += count
        }
        return tiers.isEmpty ? [(name: "CPU", cpus: 0..<cpuCount)] : tiers
    }

    // MARK: - Sampling

    private struct CPUTicks {
        var active: Double
        var total: Double
    }

    private static func sample() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        return (0..<Int(cpuCount)).map { cpu in
            let base = Int(CPU_STATE_MAX) * cpu
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            return CPUTicks(active: user + system + nice, total: user + system + nice + idle)
        }
    }

    // MARK: - sysctl

    private static func sysctlInt(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
