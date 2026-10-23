import BattisticsCore
import SwiftUI

struct KeepAwakeSessionCard: View {
    @Environment(KeepAwakeModel.self) private var awake
    @Environment(AutomationModel.self) private var automation
    @State private var windowVisible = false

    var body: some View {
        if let session = awake.session {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(automation.activeTaskName ?? awake.sessionName ?? String(localized: "Keep Awake"),
                          systemImage: "cup.and.saucer.fill")
                        .font(.callout.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Stop") { awake.stop() }.controlSize(.small)
                        .accessibilityLabel(String(localized: "Stop Keep Awake"))
                }
                HStack {
                    Text(origin)
                    Spacer()
                    Group {
                        if windowVisible, session.deadline != nil {
                            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                                Text(remainingText(at: context.date))
                            }
                        } else {
                            Text(remainingText(at: Date()))
                        }
                    }
                    .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(session.mode.label).font(.caption).foregroundStyle(.secondary)
                if awake.safety.configuration.stopOnLowBattery {
                    Text("Stops at \(awake.safety.configuration.effectiveStopPercent)% battery")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if awake.safety.configuration.stopOnThermalPressure {
                    Text("Stops under high thermal pressure")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .background(WindowVisibilityReader(isVisible: $windowVisible))
        }
    }

    private var origin: String {
        switch automation.activeSource {
        case .command: String(localized: "Terminal command")
        case .mcp: String(localized: "AI task · MCP")
        case nil: awake.sessionName == nil ? String(localized: "Started manually") : String(localized: "Profile")
        }
    }

    private func remainingText(at date: Date) -> String {
        guard let seconds = awake.remaining(at: date) else { return String(localized: "Until turned off") }
        if seconds < 60 { return String(localized: "Less than a minute left") }
        return String(localized: "\(Formatting.duration(minutes: Int(seconds / 60))) left")
    }
}
