import CSensors

struct SMCTemperatures {
    var cpu: Double?
    var gpu: Double?
}

/// Reads die temperatures out of the System Management Controller.
///
/// Sensor keys differ per SoC, so rather than hardcoding a list per machine the reader
/// enumerates every `T*` key once and keeps the ones that read back as a plausible
/// temperature. Subsequent reads only touch that shortlist.
///
/// Not thread safe: the discovery result is cached on first use, so `read()` must be
/// called from one queue.
final class SMCReader {
    private let isOpen: Bool
    private var keys: (cpu: [String], gpu: [String])?

    init() {
        isOpen = smc_open() == 1
    }

    deinit {
        if isOpen { smc_close() }
    }

    func read() -> SMCTemperatures {
        guard isOpen else { return SMCTemperatures() }
        // Discovery takes the better part of a second, so it happens on the first read
        // — on the sensor queue — rather than blocking app launch.
        let keys = self.keys ?? discoverKeys()
        return SMCTemperatures(cpu: hottest(of: keys.cpu), gpu: hottest(of: keys.gpu))
    }

    private func discoverKeys() -> (cpu: [String], gpu: [String]) {
        let all = Self.discoverTemperatureKeys()
        // `Tp*` is the performance cluster, `Te*` the efficiency cluster, `Tg*` the GPU.
        var cpu = all.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
        let gpu = all.filter { $0.hasPrefix("Tg") }

        // Older SoCs expose a single CPU die sensor instead of per-cluster ones.
        if cpu.isEmpty {
            cpu = ["TCMb", "TCHP", "TC0D", "TC0P", "TC0E"].filter { all.contains($0) }
        }

        let discovered = (cpu: cpu, gpu: gpu)
        keys = discovered
        return discovered
    }

    /// The hottest sensor in the group, which is what thermal throttling actually
    /// tracks — averaging would hide a single hot core.
    private func hottest(of keys: [String]) -> Double? {
        keys.compactMap(readTemperature).max()
    }

    private func readTemperature(_ key: String) -> Double? {
        guard isOpen else { return nil }
        let celsius = smc_read_temp(key)
        return (1...150).contains(celsius) ? celsius : nil
    }

    /// Machines expose a few hundred `T*` keys; the buffer is sized well past that so
    /// the scan is never truncated part way through the alphabet.
    private static func discoverTemperatureKeys() -> [String] {
        let capacity = 1024
        var buffer = [CChar](repeating: 0, count: capacity * 5)

        let found = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return 0 }
            return base.withMemoryRebound(to: (CChar, CChar, CChar, CChar, CChar).self,
                                          capacity: capacity) {
                smc_find_keys_with_prefix(CChar(UInt8(ascii: "T")), $0, Int32(capacity))
            }
        }

        return (0..<Int(found)).compactMap { index in
            let bytes = buffer[(index * 5)..<(index * 5 + 4)].map { UInt8(bitPattern: $0) }
            return String(bytes: bytes, encoding: .utf8)
        }
    }
}
