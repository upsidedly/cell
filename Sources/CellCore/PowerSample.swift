import CoreFoundation
import Foundation

/// One independent read of the Mac's battery and adapter telemetry.
///
/// Watt values describe power at the Mac, not consumption at the wall socket.
/// A positive `batteryWatts` means charging; a negative value means discharge.
/// Optional readings stay nil when their source is unavailable.
public struct PowerSample: Sendable, Equatable, Codable {
    public let percent: Int?
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let adapterWatts: Double?
    public let macWatts: Double?
    public let batteryWatts: Double?
    public let adapterRatedWatts: Double?
    public let sampledAt: Date

    public init(
        percent: Int?,
        isPluggedIn: Bool,
        isCharging: Bool,
        adapterWatts: Double?,
        macWatts: Double?,
        batteryWatts: Double?,
        adapterRatedWatts: Double?,
        sampledAt: Date
    ) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.adapterWatts = adapterWatts
        self.macWatts = macWatts
        self.batteryWatts = batteryWatts
        self.adapterRatedWatts = adapterRatedWatts
        self.sampledAt = sampledAt
    }

    /// Decode a single AppleSmartBattery property snapshot, without retaining
    /// previous readings. The caller supplies the time at which it was read.
    public static func decode(_ values: [String: Any], sampledAt: Date) throws -> PowerSample {
        guard sampledAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PowerReadError.invalidProperty("sampledAt")
        }
        if let installed = try flag("BatteryInstalled", in: values), !installed {
            throw PowerReadError.batteryUnavailable
        }
        guard let pluggedIn = try flag("ExternalConnected", in: values) else {
            throw PowerReadError.missingProperty("ExternalConnected")
        }
        guard let reportedCharging = try flag("IsCharging", in: values) else {
            throw PowerReadError.missingProperty("IsCharging")
        }

        // Optional sensors can report transient invalid values independently.
        // Reject that reading rather than discarding the battery's valid state.
        let telemetry = (try? dictionary("PowerTelemetryData", in: values)) ?? [:]
        let measuredInput = (try? number(
            "SystemPowerIn", in: telemetry, path: "PowerTelemetryData.SystemPowerIn",
            range: 0...1_000_000
        )).map { $0 / 1_000 }
        let measuredLoad = (try? number(
            "SystemLoad", in: telemetry, path: "PowerTelemetryData.SystemLoad",
            range: 0...1_000_000
        )).map { $0 / 1_000 }
        let rawBatteryPower = (try? signedNumber(
            "BatteryPower", in: telemetry, path: "PowerTelemetryData.BatteryPower",
            magnitudeLimit: 1_000_000
        )).map { $0 / 1_000 }

        // ExternalConnected is authoritative. Registry values from the last
        // adapter can remain present after unplugging; they are not live input.
        let adapterWatts = pluggedIn ? measuredInput : 0
        let isCharging = pluggedIn && reportedCharging
        let batteryWatts = batteryPower(
            values,
            rawPower: rawBatteryPower,
            pluggedIn: pluggedIn,
            charging: isCharging,
            adapterWatts: adapterWatts,
            measuredLoad: measuredLoad
        )

        // SystemLoad is the direct measurement. This fallback is an estimate
        // from adapter input minus battery charge, not another sensor reading.
        let derivedLoad: Double?
        if let adapterWatts, let batteryWatts {
            let load = adapterWatts - batteryWatts
            derivedLoad = load.isFinite && (0...1_000).contains(load) ? load : nil
        } else {
            derivedLoad = nil
        }

        let adapter = (try? dictionary("AdapterDetails", in: values)) ?? [:]
        let ratedWatts = try? number(
            "Watts", in: adapter, path: "AdapterDetails.Watts", range: 0...1_000
        )

        return PowerSample(
            percent: try? percentage(in: values),
            isPluggedIn: pluggedIn,
            isCharging: isCharging,
            adapterWatts: adapterWatts,
            macWatts: measuredLoad ?? derivedLoad,
            batteryWatts: batteryWatts,
            // A reported rating is a capacity, never actual consumption.
            adapterRatedWatts: pluggedIn ? ratedWatts : nil,
            sampledAt: sampledAt
        )
    }

    private static func batteryPower(
        _ values: [String: Any],
        rawPower: Double?,
        pluggedIn: Bool,
        charging: Bool,
        adapterWatts: Double?,
        measuredLoad: Double?
    ) -> Double? {
        let voltage = try? number("Voltage", in: values, range: 1...100_000)
        let current = try? signedNumber("Amperage", in: values, magnitudeLimit: 100_000)
        if let voltage, let current {
            // Top-level voltage is mV and signed current is mA. Their product
            // is microwatts. This path has an established direction convention.
            let watts = voltage * current / 1_000_000
            if watts.isFinite, abs(watts) <= 1_000 { return watts }
        }

        // BatteryPower polarity varies or is undocumented. Use only its
        // magnitude, and do not invent a direction for a holding battery.
        guard let rawPower else { return nil }
        let magnitude = abs(rawPower)
        if magnitude == 0 { return 0 }
        if !pluggedIn { return -magnitude }
        if charging { return magnitude }
        if let adapterWatts, let measuredLoad {
            let balance = adapterWatts - measuredLoad
            if balance > 0 { return magnitude }
            if balance < 0 { return -magnitude }
        }
        return nil
    }

    private static func percentage(in values: [String: Any]) throws -> Int? {
        let current = try number("CurrentCapacity", in: values, range: 0...1_000_000_000)
        let maximum = try number("MaxCapacity", in: values, range: 1...1_000_000_000)
        for (key, value) in [("CurrentCapacity", current), ("MaxCapacity", maximum)] {
            if let value, value.rounded(.towardZero) != value {
                throw PowerReadError.invalidProperty(key)
            }
        }
        guard let current, let maximum else { return nil }
        guard current <= maximum else {
            throw PowerReadError.invalidProperty("CurrentCapacity")
        }
        return Int((current / maximum * 100).rounded())
    }

    private static func dictionary(_ key: String, in values: [String: Any]) throws -> [String: Any]? {
        guard let value = values[key] else { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw PowerReadError.invalidProperty(key)
        }
        return dictionary
    }

    private static func flag(_ key: String, in values: [String: Any]) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw PowerReadError.invalidProperty(key)
        }
        return number.boolValue
    }

    private static func numericValue(_ value: Any, path: String) throws -> NSNumber {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            throw PowerReadError.invalidProperty(path)
        }
        return number
    }

    private static func number(
        _ key: String,
        in values: [String: Any],
        path: String? = nil,
        range: ClosedRange<Double>
    ) throws -> Double? {
        guard let value = values[key] else { return nil }
        let property = path ?? key
        let decoded = try numericValue(value, path: property).doubleValue
        guard range.contains(decoded) else {
            throw PowerReadError.invalidProperty(property)
        }
        return decoded
    }

    private static func signedNumber(
        _ key: String,
        in values: [String: Any],
        path: String? = nil,
        magnitudeLimit: Double
    ) throws -> Double? {
        guard let value = values[key] else { return nil }
        let property = path ?? key
        let number = try numericValue(value, path: property)
        let type = String(cString: number.objCType)
        var decoded = number.doubleValue
        if type == "Q" || type == "L" {
            // IOKit may wrap signed 64-bit current in an unsigned NSNumber.
            decoded = Double(number.int64Value)
        } else if type != "f", type != "d", decoded >= 2_147_483_648,
                  decoded <= 4_294_967_295 {
            // NSNumber can widen an unsigned 32-bit value to signed 64-bit.
            decoded = Double(Int32(bitPattern: number.uint32Value))
        }
        guard abs(decoded) <= magnitudeLimit else {
            throw PowerReadError.invalidProperty(property)
        }
        return decoded
    }
}

public enum PowerReadError: Error, Sendable, Equatable, LocalizedError {
    case batteryUnavailable
    case registryReadFailed(Int32)
    case missingProperty(String)
    case invalidProperty(String)

    public var errorDescription: String? {
        switch self {
        case .batteryUnavailable:
            return "The built-in battery is unavailable."
        case .registryReadFailed(let status):
            return "Battery telemetry could not be read (\(status))."
        case .missingProperty(let name):
            return "Battery telemetry is missing \(name)."
        case .invalidProperty(let name):
            return "Battery telemetry contains an invalid \(name) value."
        }
    }
}
