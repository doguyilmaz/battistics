import BattisticsCore
import SwiftUI

struct KeepAwakePane: View {
    @Environment(KeepAwakeModel.self) private var keepAwake
    @Environment(AppModel.self) private var model
    @Environment(PowerHelperClient.self) private var helper

    var body: some View {
        @Bindable var keepAwake = keepAwake
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Prevent this Mac from sleeping",
                        isOn: Binding(
                            get: { keepAwake.isActive },
                            set: { _ in keepAwake.toggle() }))

                    Picker("Mode", selection: $keepAwake.displayedMode) {
                        ForEach(KeepAwakeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    if let caption = keepAwake.displayedMode.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if keepAwake.displayedMode == .lidClosed, helper.needsApproval || helper.needsRepair {
                        LabeledContent {
                            Button("Go to Power") { model.dashboardPane = .power }
                        } label: {
                            Label("The power helper needs attention.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    Picker("Duration", selection: $keepAwake.displayedDuration) {
                        ForEach(KeepAwakeDuration.allCases) { duration in
                            Text(duration.label).tag(duration)
                        }
                    }

                    if let error = keepAwake.errorMessage {
                        Text(error)
                            .foregroundStyle(keepAwake.isStoppedReasonInformational ? Color.secondary : Color.red)
                    }
                    if keepAwake.isActive && keepAwake.displayedMode != .displayOn {
                        Button("Sleep Display Now") { keepAwake.sleepDisplayNow() }
                    }
                }
                .disabled(keepAwake.isChanging)
                .tourTarget(.power)
            } header: {
                InfoHeader("Keep Awake", info: "Display modes use a power assertion. Closed-lid mode also uses the power helper to temporarily disable system sleep and restore the previous setting when the session ends. If the lid is still closed then, the Mac goes to sleep as it normally would.")
            }

            // Profiles only start a session, so the running one takes their place.
            if keepAwake.isActive {
                Section("Current session") { KeepAwakeSessionCard() }
            } else {
                KeepAwakeProfiles()
            }
            KeepAwakeSafetySettings()
        }
        .formStyle(.grouped)
        .modifier(TourScrollModifier())
        .task { helper.refreshStatus() }
    }
}
