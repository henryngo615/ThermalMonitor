import ServiceManagement
import SwiftUI

// MARK: - Menu bar label (always visible)

struct MenuBarLabel: View {
    @EnvironmentObject var poller: SensorPoller

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.forTemperature(poller.readings.cpuTemp), Color.primary)
            if let temp = poller.readings.cpuTemp {
                Text("\(Int(temp))°")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .onAppear { poller.start() }
    }
}

// MARK: - Popover window

struct MenuBarView: View {
    @EnvironmentObject var poller: SensorPoller

    private var readings: Readings { poller.readings }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 8) {
                temperatures
                Divider().padding(.horizontal, 14)
                activity
                Divider().padding(.horizontal, 14)
                power
            }
            .padding(.vertical, 10)
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.1),
                                                  Color(red: 0.9, green: 0.15, blue: 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Thermal Monitor")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(poller.hasPowerData ? Color.green : Color.yellow)
                        .frame(width: 5, height: 5)
                    Text(poller.hasPowerData
                         ? "Live · \(Int(SensorPoller.interval))s"
                         : "Temperatures only")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            pressureBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pressureBadge: some View {
        let pressure = readings.thermalPressure
        return Text(pressure.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(pressure.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(pressure.color.opacity(0.12))
            .cornerRadius(5)
    }

    // MARK: Sections

    private var temperatures: some View {
        HStack(spacing: 0) {
            TempGauge(label: "CPU", temp: readings.cpuTemp, color: .blue)
            Divider().frame(height: 70)
            TempGauge(label: "GPU", temp: readings.gpuTemp, color: .purple)
        }
        .padding(.horizontal, 14)
    }

    private var activity: some View {
        VStack(spacing: 5) {
            sectionTitle("Activity", icon: "waveform.path.ecg", color: .yellow)

            ForEach(readings.cpuClusters, id: \.name) { cluster in
                LoadRow(cluster: cluster, color: cluster.name == "Efficiency" ? .mint : .blue)
                    .padding(.horizontal, 14)
            }
            if let gpu = readings.gpu {
                LoadRow(cluster: gpu, color: .purple)
                    .padding(.horizontal, 14)
            }
            if readings.cpuClusters.isEmpty && readings.gpu == nil {
                placeholder
            }
        }
    }

    private var power: some View {
        VStack(spacing: 5) {
            sectionTitle("Power", icon: "bolt.circle.fill", color: .green)

            HStack(spacing: 8) {
                if let total = readings.power.totalWatts {
                    PowerPill(label: "Total", watts: total, color: .orange)
                }
                if let cpu = readings.power.cpuWatts {
                    PowerPill(label: "CPU", watts: cpu, color: .blue)
                }
                if let gpu = readings.power.gpuWatts {
                    PowerPill(label: "GPU", watts: gpu, color: .purple)
                }
                if let dram = readings.power.dramWatts {
                    PowerPill(label: "DRAM", watts: dram, color: .teal)
                }
                if readings.power.totalWatts == nil {
                    placeholder
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func sectionTitle(_ text: String, icon: String, color: Color) -> some View {
        HStack {
            Label(text, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var placeholder: some View {
        HStack {
            Text("Waiting for data…")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            LaunchAtLoginToggle()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Sub-views

struct TempGauge: View {
    let label: String
    let temp: Double?
    let color: Color

    /// Full scale for the ring. Apple Silicon throttles well before this.
    private let ceiling: Double = 110

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat((temp ?? 0) / ceiling).clamped(to: 0...1))
                    .stroke(arcColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: temp)
                if let temp {
                    Text("\(Int(temp))°")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("--")
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 66, height: 66)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var arcColor: Color {
        temp == nil ? color : .forTemperature(temp, idle: color)
    }
}

/// How busy one cluster is, with its average clock on the right when the machine
/// publishes a DVFS table.
struct LoadRow: View {
    let cluster: ClusterLoad
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(cluster.name)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 68, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(cluster.activeResidency.clamped(to: 0...1)))
                        .animation(.easeInOut(duration: 0.4), value: cluster.activeResidency)
                }
            }
            .frame(height: 10)
            Text(trailingLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var trailingLabel: String {
        let percent = String(format: "%.0f%%", cluster.activeResidency * 100)
        guard let ghz = cluster.averageGHz else { return percent }
        return String(format: "%@ %.2fG", percent, ghz)
    }
}

struct PowerPill: View {
    let label: String
    let watts: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: watts < 10 ? "%.2fW" : "%.1fW", watts))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(7)
    }
}

/// Registers the app bundle as a login item. Only an app bundle can be a login item,
/// so the toggle hides itself when running the bare executable from a debug build.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = false

    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        if isBundled {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundColor(isEnabled ? .accentColor : .secondary)
                    Text("Open at Login")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .onAppear { isEnabled = SMAppService.mainApp.status == .enabled }
        }
    }

    private func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration can be refused (unsigned copy, quarantined bundle). Fall
            // through to re-reading the real state so the control never lies.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shared helpers

extension Color {
    /// Green below the range where Apple Silicon starts ramping fans, red once it is
    /// close to throttling.
    static func forTemperature(_ celsius: Double?, idle: Color = .green) -> Color {
        guard let celsius else { return .secondary }
        if celsius > 90 { return .red }
        if celsius > 75 { return .orange }
        return idle
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
