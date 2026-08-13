import Foundation

struct Readings {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var power = PowerSample()
    var cpuClusters: [ClusterLoad] = []
    var gpu: ClusterLoad?
    var thermalPressure: ProcessInfo.ThermalState = .nominal
    /// Nil on machines without a battery.
    var battery: BatterySample?
}

/// Samples every sensor on a background queue and republishes on the main thread.
final class SensorPoller: ObservableObject {
    @Published private(set) var readings = Readings()
    /// False when IOReport is unavailable, in which case only temperatures are shown.
    @Published private(set) var hasPowerData = false

    static let interval: TimeInterval = 2

    private let queue = DispatchQueue(label: "com.thermalmonitor.sensors", qos: .utility)
    // Both are built on the sensor queue during the first poll and only touched there.
    // Enumerating SMC keys and subscribing to IOReport together take close to a second,
    // which would otherwise stall app launch.
    private var smc: SMCReader?
    private var ioreport: IOReportSampler?
    private var processor: ProcessorLoad?
    private var battery: BatteryReader?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let smc = self.smc ?? SMCReader()
            let ioreport = self.ioreport ?? IOReportSampler()
            let processor = self.processor ?? ProcessorLoad()
            let battery = self.battery ?? BatteryReader()
            self.smc = smc
            self.ioreport = ioreport
            self.processor = processor
            self.battery = battery

            let temperatures = smc.read()
            let sampled = ioreport.sample()
            let clusters = processor.read()
            let batterySample = battery.read()
            let thermalState = ProcessInfo.processInfo.thermalState
            let powerAvailable = ioreport.isAvailable

            DispatchQueue.main.async {
                self.hasPowerData = powerAvailable
                var next = self.readings
                next.cpuTemp = temperatures.cpu
                next.gpuTemp = temperatures.gpu
                next.thermalPressure = thermalState
                next.battery = batterySample
                // The first tick has nothing to difference against, and a dropped sample
                // should not blank the panel — in both cases keep the previous numbers.
                if !clusters.isEmpty { next.cpuClusters = clusters }
                if let sampled {
                    next.power = sampled.power
                    next.gpu = sampled.gpu
                }
                self.readings = next
            }
        }
    }
}
