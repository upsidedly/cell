import Foundation
import ChargeControl
import CellCore

/// Reads the system's per-source preferences. Writes require an explicit user
/// action and the standard macOS authorization dialog, with no installed helper.
actor EnergyModeService {
    private let native = CellEnergyControl()

    func read() throws -> EnergyPreferences {
        try EnergyPreferences(values: native.readState())
    }

    func set(_ mode: EnergyMode, for source: EnergySource) async throws -> EnergyPreferences {
        let current = try read()
        guard current.setting(for: source).availableModes.contains(mode) else { throw EnergyPreferenceError.unsupportedMode }
        guard current.setting(for: source).mode != mode else { return current }
        try Task.checkCancellation()
        try await authorizeChange(mode, for: source)
        for _ in 0..<20 {
            try Task.checkCancellation()
            let state = try read()
            if state.setting(for: source).mode == mode { return state }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw EnergyPreferenceError.confirmationFailed
    }

    private func authorizeChange(_ mode: EnergyMode, for source: EnergySource) async throws {
        // Both interpolated arguments are closed enums, never user-entered text.
        // The script returns only a bounded integer; pmset's output is discarded.
        let script = """
        try
            do shell script "/usr/bin/pmset \(source.pmsetFlag) powermode \(mode.rawValue)" with administrator privileges with prompt "Cell wants to change the power mode \(source == .battery ? "on battery" : "on charger")."
            return 0
        on error number code
            return code
        end try
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer { deadline.cancel() }
        let result: Int = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let code = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    continuation.resume(returning: finished.terminationStatus == 0 ? code ?? -1 : -1)
                }
                do {
                    try Task.checkCancellation()
                    try process.run()
                    if Task.isCancelled, process.isRunning { process.terminate() }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        if result == -128 { throw EnergyPreferenceError.authorizationCancelled }
        guard result == 0 else { throw EnergyPreferenceError.changeFailed }
    }
}
