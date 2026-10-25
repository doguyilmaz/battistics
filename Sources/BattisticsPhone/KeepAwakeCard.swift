import BattisticsRemote
import SwiftUI

struct KeepAwakeCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let reachable: Bool
    @State private var message: String?

    /// 0 is "until turned off".
    @AppStorage("lastDuration") private var minutes = 60
    @AppStorage("lastMode") private var mode = RemoteStatus.Mode.displayMaySleep
    @State private var confirmingWiFi = false
    @State private var showingHotspotHelp = false
    @State private var succeeded = 0

    private static let durations = [15, 30, 60, 120, 240, 720, 0]

    var body: some View {
        let session = status.session
        let operation = store.pending[mac.id]
        let pending = operation == .start || operation == .stop

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(session == nil ? String(localized: "Keep Awake") : String(localized: "Keeping Awake"))
                        .contentTransition(.opacity)
                } icon: {
                    Image(systemName: session == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: session != nil)
                }
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
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            // Both layouts stay laid out so starting or stopping never changes the card's height.
            ZStack {
                RunningView(session: session ?? Self.placeholder, live: reachable && session != nil)
                    .opacity(session == nil ? 0 : 1)
                    .accessibilityHidden(session == nil)
                idleControls
                    .opacity(session == nil ? 1 : 0)
                    .allowsHitTesting(session == nil)
                    .accessibilityHidden(session != nil)
            }

            feedback
                .font(.footnote)
                .lineLimit(message == nil ? 1 : 2, reservesSpace: true)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(session: session, pending: pending)
        }
        .card(border: session != nil ? .orange.opacity(0.4) : nil)
        .disabled(!reachable || operation != nil)
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
            Picker("Mode", selection: Binding(get: { chosenMode }, set: { mode = $0 })) {
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
            Text("Offline. Controls return when the Mac answers.")
                .foregroundStyle(.secondary)
        } else if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        } else if status.batteryRunsOutFirst, let left = status.battery?.minutesRemaining {
            Label("Battery lasts about \(DurationLabel.long(minutes: left)), less than this.",
                  systemImage: "battery.25percent")
                .foregroundStyle(.orange)
        } else if status.needsHotspot(for: status.session?.mode ?? chosenMode) {
            Label("Turn on Hotspot before the Mac goes in a bag.", systemImage: "personalhotspot")
                .foregroundStyle(.secondary)
        } else if let session = status.session {
            Text(session.origin.label)
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
    let live: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let active = session.isActive(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if let range = session.countdownRange, active {
                            Text(timerInterval: range, countsDown: true)
                        } else if session.deadline == nil {
                            Text(session.startedAt, style: .timer)
                        } else {
                            Text("Time is up")
                        }
                    }
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    caption(active: active)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let range = session.countdownRange, active {
                    ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                } else {
                    FlowingBar(running: session.deadline == nil, animated: live)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func caption(active: Bool) -> some View {
        if let deadline = session.deadline {
            if active {
                Text("Ends \(deadline.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Waiting for the Mac")
            }
        } else {
            Label("No limit", systemImage: "infinity")
        }
    }
}

/// The track under an open-ended session: light moving along it while the Mac is kept awake.
private struct FlowingBar: View {
    let running: Bool
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(.orange.opacity(0.18))
            .overlay {
                if running, animated, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled {
                    PhaseAnimator([0.0, 1.0]) { phase in
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.linearGradient(colors: [.orange.opacity(0), .orange, .orange.opacity(0)],
                                                      startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * 0.35)
                                .offset(x: -proxy.size.width * 0.35 + phase * proxy.size.width * 1.35)
                        }
                    } animation: { phase in
                        phase == 1 ? .linear(duration: 2.2) : nil
                    }
                } else if running {
                    Capsule().fill(.orange.opacity(0.6))
                }
            }
            .clipShape(.capsule)
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}
