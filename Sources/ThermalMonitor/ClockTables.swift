import Foundation
import IOKit

/// The DVFS frequency tables the power manager publishes in the IO registry.
///
/// Each `voltage-states*` property is a list of (frequency in Hz, voltage) pairs, one
/// per performance state, ordered slowest first — the same order IOReport reports
/// state residencies in. Matching the two up turns residencies into an average clock.
///
/// Which property belongs to which domain is not documented and has moved between
/// SoC generations, so the conventional names are tried first and then any table whose
/// length matches the number of states IOReport reported. Some machines (M5 and later)
/// publish the tables with the frequencies zeroed out, in which case there is no clock
/// speed to show and callers get nil.
struct ClockTables {
    enum Domain: Hashable {
        case efficiency, performance, gpu

        /// Property names used for this domain on the SoCs where they are known.
        var conventionalKeys: [String] {
            switch self {
            case .efficiency:  return ["voltage-states1-sram", "voltage-states1"]
            case .performance: return ["voltage-states5-sram", "voltage-states5"]
            case .gpu:         return ["voltage-states9", "voltage-states9-sram"]
            }
        }
    }

    private let tables: [String: [Double]]
    private var resolved: [Domain: [Double]] = [:]

    init() {
        tables = Self.readPowerManagerTables()
    }

    /// Average frequency in GHz weighted by how long each state was occupied, or nil
    /// if this machine does not publish a usable table for the domain.
    mutating func averageGHz(for domain: Domain, states: [Double]) -> Double? {
        let frequencies = table(for: domain, stateCount: states.count)
        guard !frequencies.isEmpty else { return nil }

        let totalTicks = states.reduce(0, +)
        guard totalTicks > 0 else { return nil }

        let weighted = zip(states, frequencies).reduce(0) { $0 + $1.0 * $1.1 }
        return weighted / totalTicks / 1000
    }

    private mutating func table(for domain: Domain, stateCount: Int) -> [Double] {
        if let cached = resolved[domain] {
            return cached.count == stateCount ? cached : []
        }

        let available = tables
        let candidates = domain.conventionalKeys + available.keys.sorted()
        let match = candidates.lazy.compactMap { available[$0] }.first { $0.count == stateCount } ?? []
        resolved[domain] = match
        return match
    }

    // MARK: - IO registry

    private static func readPowerManagerTables() -> [String: [Double]] {
        guard let properties = pmgrProperties() else { return [:] }

        var tables: [String: [Double]] = [:]
        for (key, value) in properties {
            guard key.hasPrefix("voltage-states"), let data = value as? Data else { continue }
            if let megahertz = decode(data) { tables[key] = megahertz }
        }
        return tables
    }

    private static func pmgrProperties() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleARMIODevice"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS,
                  String(cString: name) == "pmgr" else { continue }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS else { continue }
            return properties?.takeRetainedValue() as? [String: Any]
        }
        return nil
    }

    /// Decodes a `voltage-states*` blob into ascending megahertz, or nil if it does not
    /// look like a frequency table on this machine.
    private static func decode(_ data: Data) -> [Double]? {
        let entrySize = MemoryLayout<UInt32>.size * 2
        guard data.count >= entrySize, data.count % entrySize == 0 else { return nil }

        var megahertz: [Double] = []
        for offset in stride(from: 0, to: data.count, by: entrySize) {
            let hertz = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            megahertz.append(Double(hertz) / 1_000_000)
        }

        // A leading zero marks the "off" state, which has no matching residency bucket.
        while megahertz.first == 0 { megahertz.removeFirst() }

        let plausible = megahertz.allSatisfy { (100...8000).contains($0) }
        let ascending = zip(megahertz, megahertz.dropFirst()).allSatisfy { $0 <= $1 }
        return !megahertz.isEmpty && plausible && ascending ? megahertz : nil
    }
}
