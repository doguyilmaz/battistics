import BattisticsCore
import SwiftUI

struct KeepAwakeSafetySettings: View {
    @Environment(KeepAwakeModel.self) private var keepAwake

    var body: some View {
        @Bindable var safety = keepAwake.safety
        Section {
            Toggle("Warn when the power adapter disconnects", isOn: $safety.configuration.warnOnAdapterDisconnect)
            ThresholdToggle("Stop Keep Awake on low battery", isOn: $safety.configuration.stopOnLowBattery,
                            percent: stopPercent, range: 5...50)
                .tourTarget(.protection)
            ThresholdToggle("Warn me before the battery runs low", isOn: $safety.configuration.warnOnLowBattery,
                            percent: warningPercent, range: safety.configuration.minimumWarningPercent...80)
            LabeledContent {
                Toggle("", isOn: $safety.configuration.stopOnThermalPressure).labelsHidden().toggleStyle(.switch)
            } label: {
                Text("Stop Keep Awake under high thermal pressure")
                Text("System thermal pressure: \(thermalLabel)")
            }
            if let warning = safety.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            InfoHeader("Session Protection",
                       info: "Only during Keep Awake. The session continues on battery with your existing protection settings.",
                       "Ends Keep Awake and allows normal sleep. It does not shut down the Mac or close your apps. Disabled by default.",
                       "Protection works while Battistics is running. A sudden charge drop may skip the warning level. Keep power connected for work that cannot be interrupted.",
                       "Warns when macOS reports serious or critical thermal pressure. The optional stop applies on battery and power adapter. Battistics does not change fan speeds; keep vents clear and never run a closed Mac in a bag.")
        }
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
