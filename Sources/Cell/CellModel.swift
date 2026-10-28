import AppKit
import ChargeControl
import CellCore
import Observation
import ServiceManagement

struct ChargeState: Sendable, Equatable, Codable {
    let limit: Int
    let availableLimits: [Int]
}

actor ChargeService {
    private var native: CellChargeControl?

    private func client() -> CellChargeControl {
        if let native { return native }
        let value = CellChargeControl()
        native = value
        return value
    }

    func read() throws -> ChargeState {
        let values = try client().readState()
        guard let limit = values["limit"] as? Int,
              let choices = values["availableLimits"] as? [Int], choices.contains(limit) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return ChargeState(limit: limit, availableLimits: choices)
    }

    func set(_ limit: Int) throws -> ChargeState {
        try client().setLimit(limit)
        return try read()
    }
}

@MainActor @Observable
final class CellModel {
    private(set) var sample: PowerSample?
    private(set) var charge: ChargeState?
    private(set) var energy: EnergyPreferences?
    private(set) var telemetryError: String?
    private(set) var chargeError: String?
    private(set) var settingsError: String?
    var energyError: String? { energyChangeError ?? energyReadError }
    private var energyReadError: String?
    private var energyChangeError: String?
    private(set) var changingEnergySource: EnergySource?
    private(set) var changingLimit = false
    var popupOpen = false
    var onUpdate: (() -> Void)?
    var onSettings: (() -> Void)?
    var showsPercentage: Bool {
        didSet { UserDefaults.standard.set(showsPercentage, forKey: "showsPercentage"); onUpdate?() }
    }
    var percentagePosition: PercentagePosition {
        didSet { UserDefaults.standard.set(percentagePosition.rawValue, forKey: "percentagePosition"); onUpdate?() }
    }
    private(set) var opensAtLogin = false
    private let reader = PowerReader()
    private let chargeService = ChargeService()
    private let energyService = EnergyModeService()
    private var polling: Task<Void, Never>?
    private var mutation: Task<Void, Never>?
    private var energyMutation: Task<Void, Never>?
    private var revision = 0
    private var energyRevision = 0

    init() {
        showsPercentage = UserDefaults.standard.object(forKey: "showsPercentage") as? Bool ?? true
        percentagePosition = UserDefaults.standard.string(forKey: "percentagePosition")
            .flatMap(PercentagePosition.init(rawValue:)) ?? .left
    }

    func start() {
        guard polling == nil else { return }
        opensAtLogin = SMAppService.mainApp.status == .enabled
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(self.popupOpen ? 1 : 5)) }
                catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel(); polling = nil
        mutation?.cancel(); mutation = nil
        energyRevision += 1
        energyMutation?.cancel(); energyMutation = nil
        // macOS owns the saved limit; quitting never resets it.
    }

    func refresh() async {
        do {
            let value = try await reader.sample()
            guard !Task.isCancelled else { return }
            sample = value; telemetryError = nil
        } catch {
            guard !Task.isCancelled else { return }
            sample = nil; telemetryError = error.localizedDescription
        }
        if !changingLimit {
            let currentRevision = revision
            do {
                let value = try await chargeService.read()
                guard !Task.isCancelled, currentRevision == revision else { return }
                charge = value; chargeError = nil
            } catch {
                guard !Task.isCancelled, currentRevision == revision else { return }
                charge = nil; chargeError = error.localizedDescription
            }
        }
        if changingEnergySource == nil {
            let currentRevision = energyRevision
            do {
                let value = try await energyService.read()
                guard !Task.isCancelled, currentRevision == energyRevision else { return }
                energy = value; energyReadError = nil
            } catch {
                guard !Task.isCancelled, currentRevision == energyRevision else { return }
                energy = nil; energyReadError = error.localizedDescription
            }
        }
        onUpdate?()
    }

    func chooseEnergyMode(_ mode: EnergyMode, for source: EnergySource) {
        guard changingEnergySource == nil, let energy,
              energy.setting(for: source).availableModes.contains(mode),
              energy.setting(for: source).mode != mode else { return }
        energyRevision += 1
        let intent = energyRevision
        changingEnergySource = source; energyChangeError = nil
        energyMutation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.energyRevision == intent {
                    self.changingEnergySource = nil; self.energyMutation = nil; self.onUpdate?()
                }
            }
            do {
                let confirmed = try await self.energyService.set(mode, for: source)
                guard !Task.isCancelled, self.energyRevision == intent else { return }
                self.energy = confirmed
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, self.energyRevision == intent else { return }
                self.energyChangeError = error.localizedDescription
            }
        }
    }

    func chooseLimit(_ limit: Int) {
        guard !changingLimit, let charge, charge.availableLimits.contains(limit), charge.limit != limit else { return }
        revision += 1
        let intent = revision
        changingLimit = true; chargeError = nil
        mutation = Task { [weak self] in
            guard let self else { return }
            defer { self.changingLimit = false; self.mutation = nil; self.onUpdate?() }
            do {
                let confirmed = try await self.chargeService.set(limit)
                guard !Task.isCancelled, intent == self.revision else { return }
                self.charge = confirmed
            } catch {
                guard !Task.isCancelled, intent == self.revision else { return }
                self.chargeError = error.localizedDescription
            }
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            opensAtLogin = SMAppService.mainApp.status == .enabled
            settingsError = SMAppService.mainApp.status == .requiresApproval ? "Allow Cell in Login Items." : nil
        } catch { settingsError = error.localizedDescription }
    }

    func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            if !NSWorkspace.shared.open(url) { chargeError = "Open Battery in System Settings." }
        }
    }

    var batteryStatus: String {
        guard let sample else { return "Unavailable" }
        if sample.isCharging { return "Charging" }
        return sample.isPluggedIn ? "On power" : "On battery"
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f W", abs(value))
    }
}
