import ActivityKit
import AppIntents
import BattisticsRemote
import SwiftUI
import WidgetKit

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
                        if let range = context.state.countdownRange {
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
                            Label("Until turned off", systemImage: "infinity")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let range = context.state.countdownRange {
                            ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(context.state.powerColor)
                        }
                        HStack(spacing: 6) {
                            Text(context.state.offline ? String(localized: "Mac not answering") : context.state.headline)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            LiveActions(context: context, size: .mini)
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
                if let range = context.state.countdownRange {
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
                    Text(watts > 0 ? "+\(Int(watts.rounded())) W" : "\(Int(watts.rounded())) W")
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
        let offline = state.offline
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
                    if let range = state.countdownRange {
                        Text(timerInterval: range, countsDown: true)
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
                        Label("Until turned off", systemImage: "infinity")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(offline ? .gray : .orange)
                // Timer text claims all the width it is offered in a widget; bound it.
                .frame(width: 100, alignment: .trailing)
            }

            if let range = state.countdownRange {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(offline ? .gray : state.powerColor)
            }

            HStack(spacing: 8) {
                LiveFreshness(state: state, quiet: offline || context.isStale)
                Spacer(minLength: 8)
                LiveActions(context: context, size: .small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Add Time for a timed session, then Stop; both act on this activity's Mac.
private struct LiveActions: View {
    let context: ActivityViewContext<KeepAwakeActivityAttributes>
    let size: ControlSize

    var body: some View {
        HStack(spacing: 6) {
            if context.state.deadline != nil {
                Button(intent: ExtendKeepAwakeLiveIntent(macID: context.attributes.macID, minutes: 30)) {
                    Label("30 min", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel(Text("Add 30 minutes"))
            }
            Button(intent: StopKeepAwakeLiveIntent(macID: context.attributes.macID)) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .controlSize(size)
        .fixedSize()
        .disabled(context.state.offline)
    }
}

/// "Updated 2 min ago" while readings arrive, "No update since 10:42" once they stopped.
private struct LiveFreshness: View {
    let state: KeepAwakeActivityAttributes.ContentState
    let quiet: Bool

    var body: some View {
        Group {
            if quiet {
                Label("No update since \(state.lastUpdate.formatted(date: .omitted, time: .shortened))",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label { Text("Updated \(Ago.text(state.lastUpdate))") } icon: { Image(systemName: "checkmark.icloud") }
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}
