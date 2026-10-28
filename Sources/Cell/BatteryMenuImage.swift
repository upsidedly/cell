import AppKit
import CellCore
import ChargeControl
import IOKit.ps

@MainActor
enum BatteryMenuImage {
    static func make(for sample: PowerSample?) -> NSImage? {
        let level = Double(sample?.percent ?? 0) / 100
        let pluggedIn = sample?.isPluggedIn ?? false
        // Golden Gate's menu bar shows the bolt for connected power, including
        // a full battery. The popup still reports actual charging telemetry.
        let charging = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? pluggedIn : sample?.isCharging ?? false
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let lowBattery = IOPSGetBatteryWarningLevel() != kIOPSLowBatteryWarningNone
        if let native = CellBatteryImage.image(level: level, charging: charging,
            pluggedIn: pluggedIn, lowPowerMode: lowPower, useRed: lowBattery) {
            return native
        }
        // Keep a current system symbol if the private renderer changes.
        let name = pluggedIn ? "battery.100percent.bolt" : "battery.100percent"
        let symbol = NSImage(systemSymbolName: name, variableValue: level, accessibilityDescription: "Battery")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        symbol?.isTemplate = true
        return symbol
    }
}
