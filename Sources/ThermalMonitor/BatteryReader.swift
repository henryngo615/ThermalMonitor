import Foundation
import IOKit

/// Which way energy is moving through the battery, and how fast.
struct BatterySample {
    enum Flow {
        case charging
        case discharging
        /// Plugged in, with the pack neither filling nor draining.
        case idle
    }

    var flow: Flow
    /// How fast the pack is filling or draining, in watts. Zero when idle.
    var watts: Double
    var isOnAC: Bool
    /// State of charge, 0...100, when the controller reports it.
    var percentage: Double?
    /// Minutes to empty while discharging, to full while charging.
    var minutesRemaining: Int?
    /// What the attached adapter can supply, when one is connected and reports it.
    var adapterWatts: Double?

    /// Positive into the battery, negative out of it.
    var signedWatts: Double { flow == .discharging ? -watts : watts }
}

/// Reads battery charge/discharge power out of the `AppleSmartBattery` IO registry entry.
///
/// The battery controller publishes pack voltage and current directly, so power is just
/// their product — no differencing between samples, unlike the IOReport energy counters.
/// While discharging this is the whole machine's draw, so it sits alongside the SoC
/// package power rather than duplicating it.
///
/// Returns nil on machines with no battery (mini, Studio, Pro), which is how the UI knows
/// not to show the section.
final class BatteryReader {
    /// Below this the pack is treated as idle rather than trickling either way, so a
    /// topped-up machine on AC does not flicker between charging and discharging.
    private static let idleThreshold = 0.05

    func read() -> BatterySample? {
        guard let properties = Self.batteryProperties() else { return nil }

        let millivolts = Double(Self.int(properties["Voltage"]) ?? 0)
        guard millivolts > 0 else { return nil }

        let milliamps = Self.amperage(properties)
        let watts = abs(Double(milliamps)) * millivolts / 1e6
        let isOnAC = Self.bool(properties["ExternalConnected"])
        let isCharging = Self.bool(properties["IsCharging"])

        let flow: BatterySample.Flow
        if watts < Self.idleThreshold {
            flow = .idle
        } else if isCharging {
            // The controller's own charging flag wins over the sign of the current,
            // which a few models publish inverted.
            flow = .charging
        } else {
            flow = milliamps > 0 ? .charging : .discharging
        }

        return BatterySample(flow: flow,
                             watts: flow == .idle ? 0 : watts,
                             isOnAC: isOnAC,
                             percentage: Self.percentage(properties),
                             minutesRemaining: Self.minutesRemaining(properties, flow: flow),
                             adapterWatts: isOnAC ? Self.adapterWatts(properties) : nil)
    }

    // MARK: - Properties

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return properties
    }

    /// Pack current in mA, negative while discharging.
    private static func amperage(_ properties: [String: Any]) -> Int {
        // `InstantAmperage` follows the load without the controller's averaging, which is
        // what a 2 second refresh wants; `Amperage` is the fallback where it is missing.
        let raw = int(properties["InstantAmperage"]) ?? int(properties["Amperage"]) ?? 0
        return signExtended(raw)
    }

    /// Some controllers publish current as an unsigned 32-bit field, so a discharge comes
    /// back as a value just under 2^32. Pack current tops out in the single-digit amps, so
    /// anything past a plausible reading is folded back into the negative range.
    private static func signExtended(_ value: Int) -> Int {
        let plausibleMilliamps = 100_000
        let wrap = Int(UInt32.max) + 1
        guard value > plausibleMilliamps, value < wrap else { return value }
        return value - wrap
    }

    private static func percentage(_ properties: [String: Any]) -> Double? {
        guard let current = int(properties["CurrentCapacity"]) else { return nil }
        // Apple Silicon reports charge as a percentage already, with `MaxCapacity` pinned
        // at 100; older controllers report both in mAh.
        guard let max = int(properties["MaxCapacity"]), max > 100 else {
            return Double(current).clamped(to: 0...100)
        }
        return (Double(current) / Double(max) * 100).clamped(to: 0...100)
    }

    private static func minutesRemaining(_ properties: [String: Any],
                                         flow: BatterySample.Flow) -> Int? {
        let key = flow == .charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        guard flow != .idle else { return nil }
        return estimate(properties[key]) ?? estimate(properties["TimeRemaining"])
    }

    /// The controller reports 65535 while it is still working out an estimate.
    private static func estimate(_ value: Any?) -> Int? {
        guard let minutes = int(value), (1..<65535).contains(minutes) else { return nil }
        return minutes
    }

    private static func adapterWatts(_ properties: [String: Any]) -> Double? {
        guard let details = properties["AdapterDetails"] as? [String: Any] else { return nil }
        if let watts = int(details["Watts"]), watts > 0 { return Double(watts) }
        // USB-C bricks that only publish what they negotiated.
        if let millivolts = int(details["Voltage"]), let milliamps = int(details["Current"]),
           millivolts > 0, milliamps > 0 {
            return Double(millivolts) * Double(milliamps) / 1e6
        }
        return nil
    }

    // MARK: - Registry values

    private static func int(_ value: Any?) -> Int? {
        // int64Value rather than intValue: the current fields are 64-bit and truncating
        // them to 32 bits is exactly the case the sign fix above has to catch.
        (value as? NSNumber).map { Int($0.int64Value) }
    }

    private static func bool(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }
}
