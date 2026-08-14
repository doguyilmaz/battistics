import BattisticsCore
import SwiftUI

/// Live controls over how this Mac behaves, as opposed to the panes that
/// only report on the battery.
struct SystemPane: View {
    @Environment(KeepAwakeModel.self) private var keepAwake
    /// Ticks with the dashboard's existing refresh loop so the countdown
    /// moves without a timer of its own.
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var keepAwake = keepAwake
        return Form {
            Section("Keep Awake") {
                Toggle(
                    "Prevent this Mac from sleeping",
                    isOn: Binding(
                        get: { keepAwake.isActive },
                        set: { _ in keepAwake.toggle() }))

                Picker("Mode", selection: $keepAwake.mode) {
                    ForEach(KeepAwakeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if let caption = keepAwake.mode.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Duration", selection: $keepAwake.duration) {
                    ForEach(KeepAwakeDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }

                if keepAwake.isActive {
                    LabeledContent("Time remaining", value: remainingText)
                }
            }

            Section {
                Text(
                    "Battistics holds a power assertion while this is on, the same mechanism the built-in caffeinate tool uses. It is released when you turn it off, when the timer runs out, or when Battistics quits."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
    }

    private var remainingText: String {
        // Reading the snapshot subscribes this view to the dashboard's
        // refresh loop, which is what re-evaluates the countdown.
        _ = model.snapshot
        guard let seconds = keepAwake.remaining() else {
            return String(localized: "Until turned off")
        }
        return Formatting.duration(minutes: Int(seconds / 60))
    }
}
