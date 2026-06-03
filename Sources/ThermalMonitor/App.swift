import SwiftUI

@main
struct ThermalMonitorApp: App {
    @StateObject private var poller = PowerMetricsPoller()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(poller)
        } label: {
            MenuBarLabel()
                .environmentObject(poller)
        }
        .menuBarExtraStyle(.window)
    }
}
