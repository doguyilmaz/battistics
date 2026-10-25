import ActivityKit
import AppIntents
import BattisticsRemote
import SwiftUI
import WidgetKit

@main
struct RemoteWidgets: WidgetBundle {
    var body: some Widget {
        MacWidget()
        MacBatteryWidget()
        MacLockScreenDetailWidget()
        KeepAwakeActivityWidget()
    }
}

struct MacProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacEntry {
        MacEntry(date: .now, snapshot: .sample(), prefs: .load())
    }

    func getSnapshot(in context: Context, completion: @escaping (MacEntry) -> Void) {
        completion(MacEntry(date: .now, snapshot: SharedSnapshot.load() ?? .sample(), prefs: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacEntry>) -> Void) {
        let now = Date.now
        let snapshot = SharedSnapshot.load()
        let prefs = WidgetPreferences.load()
        var entries = [MacEntry(date: now, snapshot: snapshot?.asOf(now), prefs: prefs)]
        // A Mac that stops writing never triggers a reload, so the offline
        // state is scheduled ahead at the moment the app would show it.
        if let snapshot, snapshot.reachable, let stale = snapshot.status?.unheardDate, stale > now {
            entries.append(MacEntry(date: stale, snapshot: snapshot.asOf(stale), prefs: prefs))
        }
        // Ending sessions change the view without new data; refresh at the deadline.
        let deadline = snapshot?.status?.session?.deadline
        let next = deadline.flatMap { $0 > now ? $0 : nil } ?? now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct MacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mac", provider: MacProvider()) { entry in
            MacWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mac Dashboard")
        .description("Battery, power, network and Keep Awake controls for your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MacBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mac.telemetry", provider: MacProvider()) { entry in
            MacTelemetryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mac Battery Telemetry")
        .description("Capacity in mAh, power, health, cycles, temperature and the last 24 hours.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MacLockScreenDetailWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mac.lockscreen.detail", provider: MacProvider()) { entry in
            MacLockScreenDetailView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mac Lock Screen")
        .description("A full-width Lock Screen widget with charge bar, power, health, cycles and the Keep Awake timer.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Live Activity Widget

struct KeepAwakeActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KeepAwakeActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.84))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: context.state.network == .hotspot ? "personalhotspot" : "laptopcomputer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(context.state.network == .hotspot ? PowerPalette.hotspot : .orange)
                            Text(context.attributes.macName)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                        LivePowerBadge(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let deadline = context.state.deadline {
                            let range = min(context.state.startedAt, deadline)...deadline
                            Text(timerInterval: range, countsDown: true)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 78, alignment: .trailing)
                            Text("Remaining")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(context.state.startedAt, style: .timer)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 78, alignment: .trailing)
                            HStack(spacing: 3) {
                                Image(systemName: "infinity")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Until stopped")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let deadline = context.state.deadline {
                            let range = min(context.state.startedAt, deadline)...deadline
                            ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(context.state.powerColor)
                        }
                        HStack(spacing: 6) {
                            Text(context.state.offline == true ? String(localized: "Mac not answering") : context.state.headline)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Button(intent: StopKeepAwakeLiveIntent()) {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.mini)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.isCharging ? "bolt.fill" : (context.state.lowPowerMode ? "leaf.fill" : "cup.and.saucer.fill"))
                        .foregroundStyle(context.state.lowPowerMode ? PowerPalette.lowPower : (context.state.isCharging ? PowerPalette.charging : .orange))
                        .symbolEffect(.pulse, isActive: context.state.isCharging)
                    if let percent = context.state.batteryPercent {
                        Text("\(percent)%")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                }
            } compactTrailing: {
                if let deadline = context.state.deadline {
                    let range = min(context.state.startedAt, deadline)...deadline
                    Text(timerInterval: range, countsDown: true)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52, alignment: .trailing)
                } else {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 46, alignment: .trailing)
                }
            } minimal: {
                Image(systemName: context.state.isCharging ? "bolt.fill" : "cup.and.saucer.fill")
                    .foregroundStyle(context.state.isCharging ? PowerPalette.charging : .orange)
            }
        }
    }
}

private struct LivePowerBadge: View {
    let state: KeepAwakeActivityAttributes.ContentState

    var body: some View {
        if let percent = state.batteryPercent {
            let color: Color = state.lowPowerMode ? PowerPalette.lowPower : (state.isCharging || state.onAdapter ? PowerPalette.charging : .white.opacity(0.85))
            HStack(spacing: 4) {
                Image(systemName: state.lowPowerMode ? "leaf.fill" : (state.isCharging ? "bolt.fill" : (state.onAdapter ? "powerplug.fill" : "battery.100")))
                    .font(.caption2.weight(.bold))
                    .symbolEffect(.pulse, isActive: state.isCharging)
                Text("\(percent)%")
                    .font(.caption.weight(.bold).monospacedDigit())
                if let watts = state.watts, abs(watts) >= 1 {
                    Text(watts > 0 ? "+\(Int(watts.rounded()))W" : "\(Int(watts.rounded()))W")
                        .font(.caption2.weight(.medium).monospacedDigit())
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
        }
    }
}

private extension KeepAwakeActivityAttributes.ContentState {
    /// One line for the session, so the mode and the lid never contradict each other.
    var headline: String {
        switch mode {
        case .lidClosed: lidClosed == false ? String(localized: "Ready to close lid") : String(localized: "Lid closed")
        case .displayOn, .displayMaySleep:
            lidClosed == true ? String(localized: "\(mode.label) · Lid closed") : mode.label
        }
    }

    var powerColor: Color {
        lowPowerMode ? PowerPalette.lowPower : (isCharging || onAdapter ? PowerPalette.charging : .orange)
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<KeepAwakeActivityAttributes>

    var body: some View {
        let state = context.state
        // `offline` comes from a real fetch; stale only means the phone heard nothing new.
        let offline = state.offline == true
        let isHotspot = state.network == .hotspot

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(context.attributes.macName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                LivePowerBadge(state: state)
            }

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill((offline ? Color.gray : .orange).opacity(0.20))
                        .frame(width: 36, height: 36)
                    Image(systemName: offline ? "wifi.slash" : state.mode.symbol)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(offline ? .gray : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Label(state.networkName ?? state.network.label, systemImage: state.network.symbol)
                        .font(.caption)
                        .foregroundStyle(isHotspot ? PowerPalette.hotspot : .white.opacity(0.72))
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    if let deadline = state.deadline {
                        Text(timerInterval: min(state.startedAt, deadline)...deadline, countsDown: true)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                        Text("Remaining")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                    } else {
                        Text(state.startedAt, style: .timer)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                        Label("Until stopped", systemImage: "infinity")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(offline ? .gray : .orange)
                .fixedSize()
            }

            if let deadline = state.deadline {
                ProgressView(timerInterval: min(state.startedAt, deadline)...deadline, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(offline ? .gray : state.powerColor)
            }

            HStack(spacing: 8) {
                LiveFreshness(state: state, quiet: offline || context.isStale)
                Spacer(minLength: 8)
                Button(intent: StopKeepAwakeLiveIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// "Updated 2 min ago" while readings arrive, "No update since 10:42" once they stopped.
private struct LiveFreshness: View {
    let state: KeepAwakeActivityAttributes.ContentState
    let quiet: Bool

    var body: some View {
        Group {
            if let last = state.lastUpdate {
                if quiet {
                    Label("No update since \(last.formatted(date: .omitted, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label { Text("Updated \(last, style: .relative) ago") } icon: { Image(systemName: "checkmark.icloud") }
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}
