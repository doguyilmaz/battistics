import BattisticsCore
import SwiftUI

struct KeepAwakeSafetySettings: View {
    @Environment(KeepAwakeModel.self) private var keepAwake

    var body: some View {
        @Bindable var safety = keepAwake.safety
        Section("Session Protection") {
            Toggle("Stop Keep Awake on low battery", isOn: $safety.configuration.stopOnLowBattery)
            if safety.configuration.stopOnLowBattery {
                Stepper(value: stopPercent, in: 5...50, step: 5) {
                    LabeledContent("Stop at", value: Formatting.percent(Double(safety.configuration.effectiveStopPercent)))
                }
                Text("Ends Keep Awake and allows normal sleep. It does not shut down the Mac or close your apps. Disabled by default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Warn me before the battery runs low", isOn: $safety.configuration.warnOnLowBattery)
            if safety.configuration.warnOnLowBattery {
                Stepper(value: warningPercent, in: minimumWarning...80, step: 5) {
                    LabeledContent("Warn at", value: Formatting.percent(Double(safety.configuration.effectiveWarningPercent)))
                }
            }
            if let warning = safety.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("Protection works while Battistics is running. A sudden charge drop may skip the warning level. Keep power connected for work that cannot be interrupted.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Thermal Care") {
            LabeledContent("System thermal pressure", value: thermalLabel)
            Toggle("Stop Keep Awake under high thermal pressure", isOn: $safety.configuration.stopOnThermalPressure)
            Text("Warns when macOS reports serious or critical thermal pressure. The optional stop applies on battery and power adapter. Battistics does not change fan speeds; keep vents clear and never run a closed Mac in a bag.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var minimumWarning: Int {
        keepAwake.safety.configuration.stopOnLowBattery
            ? keepAwake.safety.configuration.effectiveStopPercent + 5 : 10
    }

    private var stopPercent: Binding<Int> {
        Binding(get: { keepAwake.safety.configuration.effectiveStopPercent }, set: {
            var configuration = keepAwake.safety.configuration
            configuration.stopPercent = $0
            configuration.warningPercent = configuration.effectiveWarningPercent
            keepAwake.safety.configuration = configuration
        })
    }

    private var warningPercent: Binding<Int> {
        Binding(get: { keepAwake.safety.configuration.effectiveWarningPercent },
                set: { keepAwake.safety.configuration.warningPercent = $0 })
    }

    private var thermalLabel: String {
        switch keepAwake.safety.thermalState {
        case .nominal: String(localized: "Normal")
        case .fair: String(localized: "Elevated")
        case .serious: String(localized: "High")
        case .critical: String(localized: "Critical")
        @unknown default: String(localized: "Unknown")
        }
    }
}
