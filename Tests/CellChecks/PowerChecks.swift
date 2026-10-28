import Foundation
import CellCore

@main
struct CellChecks {
    static func main() throws {
        var checks = Checks()
        let time = Date(timeIntervalSince1970: 1_792_000_000)

        func read(_ changes: [String: Any] = [:]) throws -> PowerSample {
            let values: [String: Any] = [
                "ExternalConnected": true,
                "IsCharging": false,
                "CurrentCapacity": 80,
                "MaxCapacity": 100,
            ].merging(changes) { _, replacement in replacement }
            return try PowerSample.decode(values, sampledAt: time)
        }

        let charging = try read([
            "IsCharging": true,
            "Voltage": 12_000,
            "Amperage": 2_000,
            "AdapterDetails": ["Watts": 100],
            "PowerTelemetryData": ["SystemPowerIn": 44_000, "SystemLoad": 20_000, "BatteryPower": -24_000],
        ])
        checks.equal(charging.adapterWatts, 44, "actual adapter input uses milliwatts")
        checks.equal(charging.macWatts, 20, "named system load is preferred")
        checks.equal(charging.batteryWatts, 24, "signed current establishes charge direction")
        checks.equal(charging.adapterRatedWatts, 100, "adapter rating is separate from measured input")
        checks.expect(charging.isCharging && charging.isPluggedIn, "charging state")
        checks.expect(charging.percent == 80 && charging.sampledAt == time, "percentage and injected time")

        let holding = try read([
            "Voltage": 13_016,
            "Amperage": 0,
            "AdapterDetails": ["Watts": 100],
            "PowerTelemetryData": ["SystemPowerIn": 12_148, "SystemLoad": 12_148, "BatteryPower": 0],
        ])
        checks.equal(holding.adapterWatts, 12.148, "observed adapter telemetry units")
        checks.equal(holding.macWatts, 12.148, "observed system telemetry units")
        checks.equal(holding.batteryWatts, 0, "zero battery current is a valid reading")
        checks.expect(!holding.isCharging, "holding is not charging")

        let batteryOnly = try read([
            "ExternalConnected": false,
            "IsCharging": true,
            "Voltage": 12_000,
            "Amperage": -1_500,
            "AdapterDetails": ["Watts": 100],
            "PowerTelemetryData": ["SystemPowerIn": 55_000],
        ])
        checks.equal(batteryOnly.adapterWatts, 0, "unplugged ignores stale adapter input")
        checks.equal(batteryOnly.batteryWatts, -18, "battery-only draw has negative battery watts")
        checks.equal(batteryOnly.macWatts, 18, "battery-only system load can be derived")
        checks.expect(!batteryOnly.isCharging && batteryOnly.adapterRatedWatts == nil, "unplugged ignores stale adapter state and rating")

        let supplemental = try read([
            "Voltage": 12_000,
            "Amperage": -1_000,
            "PowerTelemetryData": ["SystemPowerIn": 20_000],
        ])
        checks.equal(supplemental.batteryWatts, -12, "battery can supplement a connected adapter")
        checks.equal(supplemental.macWatts, 32, "system load includes supplemental battery power")

        let unsigned64 = try read(["Voltage": 12_000, "Amperage": NSNumber(value: UInt64.max - 999)])
        checks.equal(unsigned64.batteryWatts, -12, "unsigned 64-bit two's complement current")
        let unsigned32 = try read(["Voltage": 12_000, "Amperage": NSNumber(value: UInt32.max - 999)])
        checks.equal(unsigned32.batteryWatts, -12, "widened unsigned 32-bit two's complement current")

        let chargeFallback = try read([
            "IsCharging": true,
            "PowerTelemetryData": ["SystemPowerIn": 45_000, "BatteryPower": -25_000],
        ])
        checks.equal(chargeFallback.batteryWatts, 25, "raw battery magnitude uses established charging direction")
        checks.equal(chargeFallback.macWatts, 20, "derived load subtracts battery charge")
        let dischargeFallback = try read([
            "ExternalConnected": false,
            "PowerTelemetryData": ["BatteryPower": 15_000],
        ])
        checks.equal(dischargeFallback.batteryWatts, -15, "raw battery magnitude uses unplugged direction")
        checks.equal(dischargeFallback.macWatts, 15, "raw battery fallback contributes to system draw")
        let balanceFallback = try read([
            "PowerTelemetryData": ["SystemPowerIn": 15_000, "SystemLoad": 20_000, "BatteryPower": 5_000],
        ])
        checks.equal(balanceFallback.batteryWatts, -5, "input minus load establishes supplemental direction")
        let positiveBalance = try read([
            "PowerTelemetryData": ["SystemPowerIn": 30_000, "SystemLoad": 20_000, "BatteryPower": -10_000],
        ])
        checks.equal(positiveBalance.batteryWatts, 10, "input minus load establishes positive direction")
        let unknownDirection = try read(["PowerTelemetryData": ["BatteryPower": -5_000]])
        checks.expect(unknownDirection.batteryWatts == nil, "not charging alone does not prove discharge direction")
        let equalBalance = try read([
            "PowerTelemetryData": ["SystemPowerIn": 20_000, "SystemLoad": 20_000, "BatteryPower": 5_000],
        ])
        checks.expect(equalBalance.batteryWatts == nil, "equal input and load do not establish nonzero direction")
        let zeroFallback = try read(["PowerTelemetryData": ["BatteryPower": 0]])
        checks.equal(zeroFallback.batteryWatts, 0, "raw battery zero needs no inferred direction")

        let missing = try read(["AdapterDetails": ["Watts": 100]])
        checks.expect(missing.adapterWatts == nil, "reported capacity never becomes live input")
        checks.expect(missing.macWatts == nil && missing.batteryWatts == nil, "missing sensor values remain unknown")
        let nextMissing = try read()
        checks.expect(nextMissing.adapterWatts == nil && nextMissing.macWatts == nil && nextMissing.batteryWatts == nil, "independent reads do not reuse stale optional fields")
        let noBatteryReading = try read(["PowerTelemetryData": ["SystemPowerIn": 25_000]])
        checks.expect(noBatteryReading.macWatts == nil, "unknown battery does not fabricate system load")
        let partialBattery = try read(["Voltage": 12_000])
        checks.expect(partialBattery.batteryWatts == nil, "one half of a voltage/current pair is insufficient")
        let impossibleDerived = try read([
            "IsCharging": true,
            "PowerTelemetryData": ["SystemPowerIn": 10_000, "BatteryPower": 20_000],
        ])
        checks.expect(impossibleDerived.macWatts == nil, "negative derived system load remains unknown")

        let rounded = try read(["CurrentCapacity": 1, "MaxCapacity": 3])
        checks.expect(rounded.percent == 33, "capacity ratio is rounded to a percent")
        checks.expect(try read(["CurrentCapacity": 0]).percent == 0, "zero percent is valid")
        checks.expect(try read(["CurrentCapacity": 100]).percent == 100, "full battery is valid")
        let missingCapacity = try PowerSample.decode(["ExternalConnected": true, "IsCharging": false], sampledAt: time)
        checks.expect(missingCapacity.percent == nil, "missing capacity remains unknown")

        let invalidLoads: [Any] = [-1, Double.nan, Double.infinity, 1_000_001, "bad", true,
                                  NSNumber(value: UInt64.max - 500)]
        for invalid in invalidLoads {
            let partial = try read([
                "IsCharging": true, "Voltage": 12_000, "Amperage": 2_000,
                "PowerTelemetryData": ["SystemPowerIn": 44_000, "SystemLoad": invalid],
            ])
            checks.expect(partial.percent == 80 && partial.isCharging, "invalid SystemLoad preserves battery state")
            checks.equal(partial.adapterWatts, 44, "invalid SystemLoad preserves adapter reading")
            checks.equal(partial.batteryWatts, 24, "invalid SystemLoad preserves battery reading")
            checks.equal(partial.macWatts, 20, "invalid SystemLoad falls back to power balance")
        }
        let noLoadFallback = try read(["PowerTelemetryData": ["SystemLoad": -1]])
        checks.expect(noLoadFallback.percent == 80 && noLoadFallback.macWatts == nil,
                      "invalid load without enough measurements remains unknown")

        let invalidOptionalCases: [([String: Any], String)] = [
            (["CurrentCapacity": -1], "negative capacity"),
            (["CurrentCapacity": 101], "capacity above maximum"),
            (["MaxCapacity": 0], "zero maximum capacity"),
            (["CurrentCapacity": 1.5], "fractional capacity"),
            (["Voltage": 0], "zero battery voltage"),
            (["Voltage": 100_001], "battery voltage out of range"),
            (["Amperage": 100_001], "battery current out of range"),
            (["Amperage": NSNumber(value: UInt64.max / 2)], "unsigned current out of range"),
            (["Amperage": "-1000"], "numeric strings rejected"),
            (["Amperage": true], "boolean current rejected"),
            (["PowerTelemetryData": ["SystemPowerIn": Double.nan]], "NaN power rejected"),
            (["PowerTelemetryData": ["SystemLoad": Double.infinity]], "infinite power rejected"),
            (["PowerTelemetryData": ["SystemPowerIn": -1]], "negative adapter input rejected"),
            (["PowerTelemetryData": ["SystemLoad": -1]], "negative system load rejected"),
            (["PowerTelemetryData": ["SystemPowerIn": 1_000_001]], "out of range adapter input rejected"),
            (["PowerTelemetryData": ["BatteryPower": 1_000_001]], "out of range raw battery power rejected"),
            (["PowerTelemetryData": "unavailable"], "malformed telemetry dictionary"),
            (["AdapterDetails": ["Watts": 1_001]], "out of range adapter rating"),
            (["AdapterDetails": false], "malformed adapter dictionary"),
            (["Voltage": 100_000, "Amperage": 100_000], "out of range voltage/current product"),
        ]
        for (values, name) in invalidOptionalCases {
            let partial = try read(values)
            checks.expect(partial.isPluggedIn && !partial.isCharging && partial.sampledAt == time,
                          "\(name): independent state preserved")
            checks.expect(partial.adapterWatts == nil && partial.macWatts == nil && partial.batteryWatts == nil,
                          "\(name): invalid optional readings are not displayed")
        }
        checks.rejects("numeric connection flag rejected") { _ = try read(["ExternalConnected": 1]) }
        checks.rejects("text charging flag rejected") { _ = try read(["IsCharging": "false"]) }
        checks.rejects("missing connection state") {
            _ = try PowerSample.decode(["IsCharging": false], sampledAt: time)
        }
        checks.rejects("missing charging state") {
            _ = try PowerSample.decode(["ExternalConnected": true], sampledAt: time)
        }
        checks.rejects("absent battery") {
            _ = try read(["BatteryInstalled": false])
        }
        checks.rejects("invalid sample time") {
            _ = try PowerSample.decode(["ExternalConnected": true, "IsCharging": false], sampledAt: Date(timeIntervalSince1970: .nan))
        }

        let encoded = try JSONEncoder().encode(charging)
        checks.expect(try JSONDecoder().decode(PowerSample.self, from: encoded) == charging, "immutable sample survives Codable round trip")

        let energy = try EnergyPreferences(values: [
            "battery": ["mode": 1, "availableModes": [1, 0]],
            "charger": ["mode": 2, "availableModes": [1, 0, 2]],
        ])
        checks.expect(energy.setting(for: .battery).mode == .lowPower, "battery profile has its own saved mode")
        checks.expect(energy.setting(for: .charger).mode == .highPower, "charger profile has its own saved mode")
        checks.expect(!energy.setting(for: .battery).availableModes.contains(.highPower), "unsupported battery modes stay absent")
        checks.expect(energy.setting(for: .charger).availableModes == [.lowPower, .automatic, .highPower], "native mode order is preserved")
        checks.expect(EnergySource.battery.pmsetFlag == "-b" && EnergySource.charger.pmsetFlag == "-c", "mode writes target one power source")
        checks.expect(EnergyMode.automatic.rawValue == 0 && EnergyMode.lowPower.rawValue == 1 && EnergyMode.highPower.rawValue == 2, "native power-mode values")
        let invalidEnergyRows: [[String: Any]] = [
            ["mode": 3, "availableModes": [0, 1, 2]],
            ["mode": 1.5, "availableModes": [0, 1, 2]],
            ["mode": "0", "availableModes": [0, 1]],
            ["mode": true, "availableModes": [0, 1]],
            ["mode": 2, "availableModes": [0, 1]],
            ["mode": 0, "availableModes": []],
            ["mode": 0, "availableModes": [0, 3]],
            ["mode": 0, "availableModes": [0, 0]],
            ["mode": 1, "availableModes": [1]],
        ]
        for row in invalidEnergyRows {
            do {
                _ = try EnergyPreferences(values: ["battery": row, "charger": ["mode": 0, "availableModes": [0]]])
                checks.expect(false, "invalid energy state rejected")
            } catch is EnergyPreferenceError { checks.expect(true, "invalid energy state rejected") }
        }
        do {
            _ = try EnergyPreferences(values: ["battery": ["mode": 0, "availableModes": [0]]])
            checks.expect(false, "missing charger profile rejected")
        } catch is EnergyPreferenceError { checks.expect(true, "missing charger profile rejected") }
        try checks.finish()
    }
}

private struct Checks {
    private var count = 0
    private var failures: [String] = []

    mutating func expect(_ condition: Bool, _ name: String) {
        count += 1
        if !condition { failures.append(name) }
    }

    mutating func equal(_ actual: Double?, _ expected: Double, _ name: String) {
        expect(actual.map { abs($0 - expected) < 0.000_001 } ?? false, name)
    }

    mutating func rejects(_ name: String, operation: () throws -> Void) {
        do {
            try operation()
            expect(false, name)
        } catch is PowerReadError {
            expect(true, name)
        } catch {
            expect(false, "\(name): unexpected error \(error)")
        }
    }

    mutating func finish() throws {
        for failure in failures { print("FAIL: \(failure)") }
        if !failures.isEmpty { throw CheckFailure.failed(failures.count) }
        print("\(count) Cell telemetry and energy-mode checks passed.")
    }
}

private enum CheckFailure: Error { case failed(Int) }
