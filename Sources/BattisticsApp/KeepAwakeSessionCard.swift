import BattisticsCore
import BattisticsRemote
import SwiftUI

struct KeepAwakeSessionCard: View {
    @Environment(KeepAwakeModel.self) private var awake
    @Environment(AutomationModel.self) private var automation
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppModel.self) private var model
    @State private var windowVisible = false
    /// The popover keeps to what, how long and the warning; Power shows the rest.
    var compact = false

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
                            TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
                                Text(remainingText(at: context.date))
                            }
                        } else {
                            Text(remainingText(at: Date()))
                        }
                    }
                    .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                if !compact {
                    Text(conditions(session)).font(.caption).foregroundStyle(.secondary)
                }
                if let warning = runtimeWarning(session) {
                    Label(warning, systemImage: "battery.25percent")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !compact, awake.safety.configuration.stopOnLowBattery {
                    Text("Stops at \(awake.safety.configuration.effectiveStopPercent)% battery")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !compact, awake.safety.configuration.stopOnThermalPressure {
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
        switch awake.sessionOrigin {
        case .manual: String(localized: "Started manually")
        case .profile: String(localized: "Profile")
        case .terminal: String(localized: "Terminal command")
        case .ai: String(localized: "AI task · MCP")
        case .phone: String(localized: "Started from iPhone")
        }
    }

    private func conditions(_ session: KeepAwakeSession) -> String {
        var parts = [session.mode.label, network.state.label]
        if Clamshell.read()?.isClosed == true { parts.append(String(localized: "Lid closed")) }
        return parts.joined(separator: " · ")
    }

    private func runtimeWarning(_ session: KeepAwakeSession) -> String? {
        guard let snapshot = model.snapshot, snapshot.batteryInstalled, let minutes = snapshot.timeRemainingMin,
              RemoteStatus.batteryRunsOutFirst(minutesLeft: minutes, onAdapter: snapshot.externalConnected,
                                               deadline: session.deadline, now: Date()) else { return nil }
        return String(localized: "Battery lasts about \(Formatting.duration(minutes: minutes))")
    }

    private func remainingText(at date: Date) -> String {
        guard let seconds = awake.remaining(at: date) else { return String(localized: "Until turned off") }
        if seconds < 60 { return String(localized: "Less than a minute left") }
        return String(localized: "\(Formatting.duration(minutes: Int(seconds / 60))) left")
    }
}
