import Foundation

struct ThermalData {
    var cpuDieTemp: Double?
    var gpuDieTemp: Double?
    var cpuClusterFreqs: [(name: String, freq: Double)] = []
    var gpuFreq: Double?
    var packagePower: Double?
    var cpuPower: Double?
    var gpuPower: Double?
    var thermalPressure: String?
}

class PowerMetricsPoller: ObservableObject {
    @Published var data = ThermalData()
    @Published var isRunning = false
    @Published var sudoReady = false
    @Published var error: String?

    private var timer: Timer?
    private let smc = SMCReader()
    private let queue = DispatchQueue(label: "com.thermalmonitor.poll", qos: .utility)

    func start() {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func poll() {
        queue.async { [weak self] in
            self?.runPowermetrics()
        }
    }

    private func runPowermetrics() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/powermetrics",
                          "--samplers", "cpu_power,gpu_power,thermal",
                          "-n", "1", "-i", "500", "--format", "plist"]

        // Isolate all stdio so sudo never tries to open a terminal
        proc.standardInput  = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        let outPipe = Pipe()
        proc.standardOutput = outPipe

        proc.launch()
        let raw = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard !raw.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: raw, format: nil),
              let dict = plist as? [String: Any] else {
            let smcTemps = SMCTemps.read(from: smc)
            DispatchQueue.main.async {
                self.sudoReady = false
                if smcTemps.cpuDie == nil && smcTemps.gpuDie == nil {
                    self.error = "Requires sudo for powermetrics.\n\nRun in Terminal:\nsudo powermetrics -n 1 --format plist > /dev/null"
                } else {
                    // SMC-only mode: no powermetrics but we have temps
                    var d = ThermalData()
                    d.cpuDieTemp = smcTemps.cpuDie
                    d.gpuDieTemp = smcTemps.gpuDie
                    self.data = d
                    self.error = nil
                }
            }
            return
        }

        let parsed = parse(dict: dict)
        DispatchQueue.main.async {
            self.sudoReady = true
            self.data = parsed
            self.error = nil
        }
    }

    private func parse(dict: [String: Any]) -> ThermalData {
        var result = ThermalData()

        result.thermalPressure = dict["thermal_pressure"] as? String

        if let processor = dict["processor"] as? [String: Any] {
            result.packagePower = processor["package_watts"] as? Double

            if let clusters = processor["clusters"] as? [[String: Any]] {
                for cluster in clusters {
                    let name = cluster["name"] as? String ?? "CPU"
                    if let freq = cluster["freq_hz"] as? Double {
                        result.cpuClusterFreqs.append((name: name, freq: freq / 1_000_000_000))
                    }
                }
            }
            if let mJ = processor["cpu_energy"] as? Double { result.cpuPower = mJ / 500.0 }
            if let mJ = processor["gpu_energy"] as? Double { result.gpuPower = mJ / 500.0 }
        }

        if let gpu = dict["gpu"] as? [String: Any] {
            if let hz = gpu["freq_hz"] as? Double { result.gpuFreq = hz / 1_000_000 }
        }

        // SMC temps (powermetrics thermal sampler is empty on Apple Silicon)
        let smcTemps = SMCTemps.read(from: smc)
        result.cpuDieTemp = smcTemps.cpuDie
        result.gpuDieTemp = smcTemps.gpuDie

        return result
    }
}
