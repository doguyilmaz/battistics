import BattisticsRemote
import SwiftUI

struct KeepAwakeCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let reachable: Bool
    @Binding var message: String?

    /// 0 is "until turned off".
    @AppStorage("lastDuration") private var minutes = 60
    @AppStorage("lastMode") private var mode = RemoteStatus.Mode.displayMaySleep
    @State private var confirmingWiFi = false
    @State private var showingHotspotHelp = false
    @State private var succeeded = 0

    private static let durations = [15, 30, 60, 120, 240, 720, 0]

    var body: some View {
        let session = status.session
        let pending = store.pending.contains(mac.id)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(session == nil ? String(localized: "Keep Awake") : String(localized: "Keeping Awake"),
                      systemImage: session == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(session == nil ? Color.primary : .orange)
                Spacer()
                if let session {
                    Label(session.mode.label, systemImage: session.mode.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: .capsule)
                        .foregroundStyle(.orange)
                }
            }

            // Both layouts stay laid out so starting or stopping never changes the card's height.
            ZStack {
                RunningView(session: session ?? Self.placeholder)
                    .opacity(session == nil ? 0 : 1)
                    .accessibilityHidden(session == nil)
                idleControls
                    .opacity(session == nil ? 1 : 0)
                    .allowsHitTesting(session == nil)
                    .accessibilityHidden(session != nil)
            }

            feedback
                .font(.footnote)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(session: session, pending: pending)
        }
        .card(border: session != nil ? .orange.opacity(0.4) : nil)
        .disabled(!reachable || pending)
        .animation(.snappy, value: session != nil)
        .sensoryFeedback(.success, trigger: succeeded)
        .onChange(of: session) { message = nil }
        .onChange(of: mode) { message = nil }
        .onChange(of: minutes) { message = nil }
        .confirmationDialog("The Mac is on Wi‑Fi, not Hotspot", isPresented: $confirmingWiFi, titleVisibility: .visible) {
            Button("Start Anyway") { start(.lidClosed) }
            Button("How to Turn On Hotspot") { showingHotspotHelp = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wi‑Fi drops once the Mac leaves its range in a bag, and so does remote control. Personal Hotspot keeps it online.")
        }
        .hotspotHelp(isPresented: $showingHotspotHelp)
    }

    private var modes: [RemoteStatus.Mode] {
        status.protection.closedLidAllowed ? [.displayMaySleep, .displayOn, .lidClosed] : [.displayMaySleep, .displayOn]
    }

    private var chosenMode: RemoteStatus.Mode { modes.contains(mode) ? mode : .displayMaySleep }

    private var idleControls: some View {
        VStack(spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(modes, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                ForEach(Self.durations, id: \.self) { value in
                    let selected = value == minutes
                    Button {
                        minutes = value
                    } label: {
                        Text(DurationLabel.short(value))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DurationLabel.spoken(minutes: value))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: minutes)
            .animation(.snappy, value: minutes)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if !reachable {
            Text("The Mac is offline or asleep. Controls come back when it answers.")
                .foregroundStyle(.secondary)
        } else if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        } else if status.batteryRunsOutFirst, let left = status.battery?.minutesRemaining {
            Label("The battery lasts about \(DurationLabel.long(minutes: left)), less than this session.",
                  systemImage: "battery.25percent")
                .foregroundStyle(.orange)
        } else if status.needsHotspot(for: status.session?.mode ?? chosenMode) {
            Label("Not on Hotspot. Turn it on before the Mac goes in a bag.", systemImage: "personalhotspot")
                .foregroundStyle(.secondary)
        } else if let session = status.session {
            Text("\(session.mode.subtitle) · \(session.origin.label)")
                .foregroundStyle(.secondary)
        } else {
            Text(chosenMode.subtitle)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionButton(session: RemoteStatus.Session?, pending: Bool) -> some View {
        if session != nil {
            Button(role: .destructive) {
                run { await store.stop(mac) }
            } label: {
                buttonLabel(String(localized: "Stop"), symbol: "stop.fill", pending: pending)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else {
            Button {
                if status.needsHotspot(for: chosenMode) { confirmingWiFi = true } else { start(chosenMode) }
            } label: {
                buttonLabel(minutes == 0
                            ? String(localized: "Keep Awake Until Turned Off")
                            : String(localized: "Keep Awake for \(DurationLabel.long(minutes: minutes))"),
                            symbol: "cup.and.saucer.fill", pending: pending)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func buttonLabel(_ title: String, symbol: String, pending: Bool) -> some View {
        HStack(spacing: 6) {
            if pending { ProgressView().tint(.white) } else { Image(systemName: symbol) }
            Text(title).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }

    private func start(_ mode: RemoteStatus.Mode) {
        run { await store.start(mac, mode: mode, minutes: minutes) }
        Task { await Notifications.requestPermission() }
    }

    private func run(_ action: @escaping () async -> String?) {
        Task {
            message = nil
            let failure = await action()
            message = failure
            if failure == nil { succeeded += 1 }
        }
    }

    private static let placeholder = RemoteStatus.Session(mode: .displayMaySleep, origin: .phone, startedAt: .now, deadline: .now)
}

private struct RunningView: View {
    let session: RemoteStatus.Session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if let range = session.countdownRange, session.isActive(at: context.date) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                } else if session.deadline == nil {
                    Text(session.startedAt, style: .timer)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Label("Until turned off", systemImage: "infinity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Time is up")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Waiting for the Mac to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
