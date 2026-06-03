import CSMC

class SMCReader {
    let isOpen: Bool

    init() { isOpen = smc_open() == 1 }
    deinit { smc_close() }

    func readTemperature(_ key: String) -> Double? {
        guard isOpen else { return nil }
        let t = smc_read_temp(key)
        return (t > 1 && t < 150) ? t : nil
    }

    // Returns all live T-prefixed keys grouped by their second character:
    // 'p' = P-cluster (CPU perf), 'e' = E-cluster (CPU eff), 'g' = GPU, etc.
    func discoverTemps() -> (cpu: Double?, gpu: Double?) {
        guard isOpen else { return (nil, nil) }

        let maxKeys = 256
        var buf = [[CChar]](repeating: [CChar](repeating: 0, count: 5), count: maxKeys)
        var flatBuf = buf.flatMap { $0 }

        let count = flatBuf.withUnsafeMutableBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return 0 }
            return smc_find_keys_with_prefix(CChar(UInt8(ascii: "T")), base.assumingMemoryBound(to: (CChar, CChar, CChar, CChar, CChar).self), Int32(maxKeys))
        }

        guard count > 0 else { return (nil, nil) }

        // Rebuild key strings
        var keys: [String] = []
        for i in 0..<Int(count) {
            let start = i * 5
            let slice = Array(flatBuf[start..<(start+4)])
            if let s = String(bytes: slice.map { UInt8(bitPattern: $0) }, encoding: .utf8) {
                keys.append(s)
            }
        }

        // CPU: average of Tp* (P-cluster) keys, falling back to Te* (E-cluster)
        // GPU: average of Tg* keys
        // We exclude obviously board/ambient keys (TB, TA, TV, Ts, TCHP etc.)
        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []

        for key in keys {
            guard let t = readTemperature(key) else { continue }
            let second = key.dropFirst().first
            switch second {
            case "p": cpuTemps.append(t)   // Tp* — P-cluster
            case "e": cpuTemps.append(t)   // Te* — E-cluster
            case "g": gpuTemps.append(t)   // Tg* — GPU
            default: break
            }
        }

        // Fall back to TCMb / TCHP if no cluster keys found (some models)
        if cpuTemps.isEmpty {
            for key in ["TCMb", "TCHP", "TC0D", "TC0P", "TC0E"] {
                if let t = readTemperature(key) { cpuTemps.append(t); break }
            }
        }

        let cpu = cpuTemps.isEmpty ? nil : cpuTemps.max()
        let gpu = gpuTemps.isEmpty ? nil : gpuTemps.max()
        return (cpu, gpu)
    }
}

struct SMCTemps {
    var cpuDie: Double?
    var gpuDie: Double?

    static func read(from smc: SMCReader) -> SMCTemps {
        let (cpu, gpu) = smc.discoverTemps()
        return SMCTemps(cpuDie: cpu, gpuDie: gpu)
    }
}
