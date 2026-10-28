import CoreFoundation
import Foundation

public enum EnergyMode: Int, Sendable, Codable, CaseIterable {
    case automatic = 0, lowPower = 1, highPower = 2

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .lowPower: "Low Power"
        case .highPower: "High Power"
        }
    }
}

public enum EnergySource: String, Sendable, CaseIterable, Identifiable {
    case battery, charger
    public var id: String { rawValue }
    public var title: String { self == .battery ? "On battery" : "On charger" }
    public var pmsetFlag: String { self == .battery ? "-b" : "-c" }
}

public struct EnergySetting: Sendable, Equatable {
    public let mode: EnergyMode
    public let availableModes: [EnergyMode]
}

public struct EnergyPreferences: Sendable, Equatable {
    private let battery: EnergySetting
    private let charger: EnergySetting

    public init(values: [String: Any]) throws {
        func setting(_ source: EnergySource) throws -> EnergySetting {
            guard let row = values[source.rawValue] as? [String: Any],
                  let number = row["mode"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.intValue),
                  let mode = EnergyMode(rawValue: number.intValue),
                  let rawChoices = row["availableModes"] as? [Int],
                  !rawChoices.isEmpty else { throw EnergyPreferenceError.invalidState }
            let choices = rawChoices.compactMap(EnergyMode.init(rawValue:))
            guard choices.count == rawChoices.count, Set(choices).count == choices.count,
                  choices.contains(.automatic), choices.contains(mode) else { throw EnergyPreferenceError.invalidState }
            return EnergySetting(mode: mode, availableModes: choices)
        }
        battery = try setting(.battery)
        charger = try setting(.charger)
    }

    public func setting(for source: EnergySource) -> EnergySetting { source == .battery ? battery : charger }
}

public enum EnergyPreferenceError: Error, LocalizedError {
    case invalidState, unsupportedMode, authorizationCancelled, changeFailed, confirmationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidState: "Power modes could not be read. Open Battery Settings to check them."
        case .unsupportedMode: "This power mode is not available for the selected power source."
        case .authorizationCancelled: "Power mode change cancelled."
        case .changeFailed: "macOS did not change the power mode. Try again or use Battery Settings."
        case .confirmationFailed: "macOS has not confirmed the new power mode. Check Battery Settings."
        }
    }
}
