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
        let entry = MacEntry(date: .now, snapshot: .load(), prefs: .load())
        // Ending sessions change the view without new data; refresh at the deadline.
        let deadline = entry.snapshot?.status?.session?.deadline
        let next = deadline.flatMap { $0 > .now ? $0 : nil } ?? .now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
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
                                .tint(context.state.lowPowerMode ? PowerPalette.lowPower : (context.state.isCharging ? PowerPalette.charging : .orange))
                        }
                        HStack(spacing: 6) {
                            Label(context.state.mode.label, systemImage: context.state.mode.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let closed = context.state.lidClosed {
                                Text("·").foregroundStyle(.secondary)
                                Text(closed ? String(localized: "Lid closed") : String(localized: "Lid open"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
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

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<KeepAwakeActivityAttributes>

    var body: some View {
        let state = context.state
        let isHotspot = state.network == .hotspot
        let powerColor: Color = state.lowPowerMode
            ? PowerPalette.lowPower
            : (state.isCharging || state.onAdapter ? PowerPalette.charging : .orange)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isHotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : powerColor)
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
                        .fill(Color.orange.opacity(0.20))
                        .frame(width: 36, height: 36)
                    Image(systemName: state.mode.symbol)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse, isActive: true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.mode.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let closed = state.lidClosed {
                            Text(closed ? String(localized: "Lid closed") : String(localized: "Lid open"))
                        }
                        Text("·")
                        Text(state.networkName ?? state.network.label)
                            .foregroundStyle(isHotspot ? PowerPalette.hotspot : .white.opacity(0.72))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                if let deadline = state.deadline {
                    let range = min(state.startedAt, deadline)...deadline
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90, alignment: .trailing)
                        Text("Remaining")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.startedAt, style: .timer)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90, alignment: .trailing)
                        HStack(spacing: 3) {
                            Image(systemName: "infinity")
                                .font(.system(size: 10, weight: .bold))
                            Text("Until stopped")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }

            if let deadline = state.deadline {
                let range = min(state.startedAt, deadline)...deadline
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(powerColor)
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: state.isCharging ? "bolt.fill" : "cup.and.saucer.fill")
                        .font(.caption2)
                        .foregroundStyle(powerColor)
                    Text(state.isCharging
                         ? String(localized: "Charging on adapter")
                         : (state.onAdapter ? String(localized: "On power adapter") : String(localized: "Keeping Mac awake")))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
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
