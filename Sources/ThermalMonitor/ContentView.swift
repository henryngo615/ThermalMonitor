import SwiftUI

// MARK: - Menu bar label (always visible)

struct MenuBarLabel: View {
    @EnvironmentObject var poller: PowerMetricsPoller

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
                .symbolRenderingMode(.palette)
                .foregroundStyle(tempColor(poller.data.cpuDieTemp), Color.primary)
            if let t = poller.data.cpuDieTemp {
                Text("\(Int(t))°")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .onAppear { poller.start() }
    }

    func tempColor(_ t: Double?) -> Color {
        guard let t else { return .secondary }
        if t > 90 { return .red }
        if t > 75 { return .orange }
        return .green
    }
}

// MARK: - Popover window

struct MenuBarView: View {
    @EnvironmentObject var poller: PowerMetricsPoller

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let err = poller.error {
                errorView(err)
            } else {
                mainContent
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(red:1,green:0.45,blue:0.1),
                                                   Color(red:0.9,green:0.15,blue:0.15)],
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
                        .fill(poller.sudoReady ? Color.green : Color.yellow)
                        .frame(width: 5, height: 5)
                    Text(poller.sudoReady ? "Live · 3s" : "Limited mode")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let p = poller.data.thermalPressure {
                pressureBadge(p)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func pressureBadge(_ pressure: String) -> some View {
        Text(pressure.capitalized)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(pressureColor(pressure))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(pressureColor(pressure).opacity(0.12))
            .cornerRadius(5)
    }

    // MARK: Main content (no ScrollView = no lag)

    var mainContent: some View {
        VStack(spacing: 8) {
            tempRow
            Divider().padding(.horizontal, 14)
            clockSection
            Divider().padding(.horizontal, 14)
            powerRow
        }
        .padding(.vertical, 10)
    }

    var tempRow: some View {
        HStack(spacing: 0) {
            TempGauge(label: "CPU", temp: poller.data.cpuDieTemp, color: .blue)
            Divider().frame(height: 70)
            TempGauge(label: "GPU", temp: poller.data.gpuDieTemp, color: .purple)
        }
        .padding(.horizontal, 14)
    }

    var clockSection: some View {
        VStack(spacing: 5) {
            HStack {
                Label("Clock Speed", systemImage: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.yellow)
                Spacer()
            }
            .padding(.horizontal, 14)

            ForEach(poller.data.cpuClusterFreqs, id: \.name) { c in
                ClockRow(label: c.name, value: c.freq, unit: "GHz", max: 4.0,
                         color: c.name.lowercased().hasPrefix("e") ? .mint : .blue)
                    .padding(.horizontal, 14)
            }
            if let gpuFreq = poller.data.gpuFreq, gpuFreq > 0 {
                ClockRow(label: "GPU", value: gpuFreq / 1000, unit: "GHz", max: 1.4, color: .purple)
                    .padding(.horizontal, 14)
            }
            if poller.data.cpuClusterFreqs.isEmpty {
                Text("Waiting for data…")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 14)
            }
        }
    }

    var powerRow: some View {
        VStack(spacing: 5) {
            HStack {
                Label("Power", systemImage: "bolt.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.horizontal, 14)

            HStack(spacing: 8) {
                if let pkg = poller.data.packagePower {
                    PowerPill(label: "Package", watts: pkg, color: .orange)
                }
                if let cpu = poller.data.cpuPower {
                    PowerPill(label: "CPU", watts: cpu, color: .blue)
                }
                if let gpu = poller.data.gpuPower {
                    PowerPill(label: "GPU", watts: gpu, color: .purple)
                }
                if poller.data.packagePower == nil && poller.data.cpuPower == nil {
                    Text("Waiting…").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: Error

    func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permission Required", systemImage: "lock.shield")
                .font(.subheadline.bold()).foregroundColor(.orange)
            Text(msg)
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Terminal to Authenticate") {
                let script = """
                tell application "Terminal"
                    activate
                    do script "sudo powermetrics -n 1 -i 500 --format plist > /dev/null"
                end tell
                """
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    var footer: some View {
        HStack {
            Spacer()
            Button("Quit ThermalMonitor") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func pressureColor(_ p: String) -> Color {
        switch p.lowercased() {
        case "nominal":  return .green
        case "moderate": return .yellow
        case "heavy":    return .orange
        case "critical": return .red
        default:         return .secondary
        }
    }
}

// MARK: - Sub-views

struct TempGauge: View {
    let label: String
    let temp: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat((temp ?? 0) / 110).clamped(to: 0...1))
                    .stroke(arcColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: temp)
                Group {
                    if let t = temp {
                        Text("\(Int(t))°")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("--")
                            .font(.system(size: 18, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 66, height: 66)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    var arcColor: Color {
        guard let t = temp else { return color }
        if t > 90 { return .red }
        if t > 75 { return .orange }
        return color
    }
}

struct ClockRow: View {
    let label: String
    let value: Double
    let unit: String
    let max: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 62, alignment: .leading)
                .foregroundColor(.primary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat((value / max).clamped(to: 0...1)))
                        .animation(.easeInOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 10)
            Text(String(format: "%.2f %@", value, unit))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

struct PowerPill: View {
    let label: String
    let watts: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1fW", watts))
                .font(.system(size: 13, weight: .bold, design: .rounded))
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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
