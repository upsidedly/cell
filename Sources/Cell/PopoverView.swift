import AppKit
import SwiftUI
import CellCore

struct PopoverView: View {
    @Bindable var model: CellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(model.sample?.percent.map { "\($0)%" } ?? "—", systemImage: "battery.75percent")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(model.batteryStatus).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                power("Adapter", symbol: "powerplug", watts: model.sample?.adapterWatts)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                power("Mac", symbol: "laptopcomputer", watts: model.sample?.macWatts)
                Image(systemName: batteryArrow).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                power(batteryLabel, symbol: "battery.75percent", watts: model.sample?.batteryWatts)
            }
            .padding(.vertical, 4)
            if let error = model.telemetryError {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text("Charge limit").font(.system(size: 13))
                Spacer()
                if let charge = model.charge {
                    Picker("Charge limit", selection: Binding(get: { charge.limit }, set: { model.chooseLimit($0) })) {
                        ForEach(charge.availableLimits, id: \.self) { limit in
                            Text("\(limit)%").tag(limit)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 84)
                    .disabled(model.changingLimit)
                    .accessibilityIdentifier("cell-charge-limit")
                    .help("macOS keeps this limit when Cell quits. It may occasionally charge to 100% for calibration.")
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if let error = model.chargeError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Battery Settings") { model.openBatterySettings() }.font(.system(size: 12))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Energy mode").font(.system(size: 11)).foregroundStyle(.secondary)
                    if model.changingEnergySource != nil {
                        ProgressView().controlSize(.mini).accessibilityLabel("Changing power mode")
                    }
                }
                ForEach(EnergySource.allCases) { source in
                    HStack {
                        Text(source.title).font(.system(size: 13))
                        Spacer()
                        if let setting = model.energy?.setting(for: source) {
                            Picker(source.title, selection: Binding(get: { setting.mode }, set: { model.chooseEnergyMode($0, for: source) })) {
                                ForEach(setting.availableModes, id: \.self) { mode in Text(mode.title).tag(mode) }
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 124)
                            .disabled(model.changingEnergySource != nil)
                            .accessibilityLabel("\(source.title) power mode")
                            .accessibilityIdentifier("cell-energy-\(source.rawValue)")
                            .help("macOS saves this mode for \(source == .battery ? "battery" : "charger") use. Changing it requires authorization.")
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = model.energyError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Battery Settings") { model.openBatterySettings() }.font(.system(size: 12))
                }
            }
            HStack {
                Button { model.onSettings?() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                    .accessibilityIdentifier("cell-settings")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(width: 310)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var batteryLabel: String {
        guard let watts = model.sample?.batteryWatts else { return "Battery" }
        if watts > 0.1 { return "Charging" }
        if watts < -0.1 { return "Battery out" }
        return "Battery"
    }

    private var batteryArrow: String {
        guard let watts = model.sample?.batteryWatts else { return "minus" }
        if watts > 0.1 { return "chevron.right" }
        if watts < -0.1 { return "chevron.left" }
        return "minus"
    }

    private func power(_ name: String, symbol: String, watts: Double?) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular)).frame(height: 22)
            Text(CellModel.watts(watts)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .minimumScaleFactor(0.8).lineLimit(1)
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name).accessibilityValue(CellModel.watts(watts))
    }
}

struct SettingsView: View {
    @Bindable var model: CellModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Show percentage in menu bar", isOn: $model.showsPercentage)
            HStack {
                Text("Percentage position")
                Spacer()
                Picker("Percentage position", selection: $model.percentagePosition) {
                    ForEach(PercentagePosition.allCases) { position in Text(position.title).tag(position) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 120)
                .disabled(!model.showsPercentage)
                .accessibilityIdentifier("cell-percentage-position")
            }
            Toggle("Open at login", isOn: Binding(get: { model.opensAtLogin }, set: { model.setLogin($0) }))
            if let error = model.settingsError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Battery Settings") { model.openBatterySettings() }
                Spacer()
                Text("Cell 1.0").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch).font(.system(size: 13))
        .padding(22).frame(width: 340).fixedSize(horizontal: false, vertical: true)
    }
}
