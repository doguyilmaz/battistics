import ActivityKit
import AppIntents
import BattisticsRemote
import SwiftUI
import WidgetKit

@main
struct RemoteWidgets: WidgetBundle {
    var body: some Widget {
        MacWidget()
        KeepAwakeActivityWidget()
    }
}

struct MacEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct MacProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacEntry {
        MacEntry(date: .now, snapshot: .init(
            macName: "MacBook Pro",
            status: .init(
                machineName: "MacBook Pro",
                readAt: .now,
                battery: .init(percent: 86, isCharging: true, onAdapter: true, minutesRemaining: 35, healthPercent: 94, lowPowerMode: false, watts: 42, adapterWatts: 67),
                session: .init(mode: .displayMaySleep, origin: .phone, name: "Started from iPhone",
                               startedAt: .now.addingTimeInterval(-600), deadline: .now.addingTimeInterval(3000)),
                network: .wifi,
                networkName: "Home Wi‑Fi",
                lidClosed: false,
                thermal: .nominal
            ),
            lastSeen: .now, reachable: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (MacEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MacEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacEntry>) -> Void) {
        let entry = MacEntry(date: .now, snapshot: .load())
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
        .configurationDisplayName("Mac")
        .description("Battery, power state, hotspot link, and Keep Awake countdown for your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacEntry

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .accessoryInline: inline(snapshot, status)
            case .accessoryCircular: circular(status)
            case .accessoryRectangular: rectangular(snapshot, status)
            case .systemMedium: medium(snapshot, status)
            default: small(snapshot, status)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "laptopcomputer.and.iphone").font(.title2).foregroundStyle(.tint)
                Text("Open Battistics Remote").font(.caption.weight(.semibold))
                Text("Turn on iPhone access in Battistics on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: Lock Screen Widgets

    @ViewBuilder
    private func inline(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let percent = status.battery.map { "\($0.percent)%" } ?? snapshot.macName
        if let session = status.session, let deadline = session.deadline, deadline > entry.date {
            let range = min(session.startedAt, deadline)...deadline
            Label {
                Text("\(percent) · \(Text(timerInterval: range, countsDown: true))")
            } icon: {
                Image(systemName: status.network == .hotspot ? "personalhotspot" : "cup.and.saucer.fill")
            }
        } else if status.session != nil {
            Label("\(percent) · Awake ∞", systemImage: "cup.and.saucer.fill")
        } else if status.network == .hotspot {
            Label("\(snapshot.macName) \(percent) · Hotspot", systemImage: "personalhotspot")
        } else {
            Label("\(snapshot.macName) \(percent)", systemImage: status.battery?.isCharging == true ? "bolt.fill" : "laptopcomputer")
        }
    }

    private func circular(_ status: RemoteStatus) -> some View {
        let active = isSessionActive(status)
        let symbol: String = {
            if active { return "cup.and.saucer.fill" }
            if status.battery?.lowPowerMode == true { return "leaf.fill" }
            if status.battery?.isCharging == true { return "bolt.fill" }
            if status.network == .hotspot { return "personalhotspot" }
            return "laptopcomputer"
        }()
        return Gauge(value: Double(status.battery?.percent ?? 0), in: 0...100) {
            Image(systemName: symbol)
        } currentValueLabel: {
            Text(status.battery.map { "\($0.percent)" } ?? "–")
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let active = isSessionActive(status)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: status.network == .hotspot ? "personalhotspot" : (active ? "cup.and.saucer.fill" : "laptopcomputer"))
                Text(snapshot.macName).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let battery = status.battery {
                    HStack(spacing: 2) {
                        if battery.lowPowerMode == true {
                            Image(systemName: "leaf.fill").font(.caption2)
                        } else if battery.isCharging {
                            Image(systemName: "bolt.fill").font(.caption2)
                        } else if battery.onAdapter {
                            Image(systemName: "powerplug.fill").font(.caption2)
                        }
                        Text("\(battery.percent)%").font(.headline.monospacedDigit())
                    }
                }
            }
            if let session = status.session, let deadline = session.deadline, deadline > entry.date {
                let range = min(session.startedAt, deadline)...deadline
                HStack(spacing: 4) {
                    Text(session.mode.label).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(timerInterval: range, countsDown: true)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            } else if let session = status.session, session.deadline == nil {
                HStack(spacing: 4) {
                    Text("∞ · \(session.mode.label)").lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(session.startedAt, style: .timer)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 58, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(batterySubtitle(status.battery))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 5) {
                    Text(status.networkDisplayLabel())
                    if let closed = status.lidClosed {
                        Text("·")
                        Text(closed ? String(localized: "Closed") : String(localized: "Open"))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen Widgets

    private func small(_ snapshot: SharedSnapshot, _ status: RemoteStatus, showsControls: Bool = true) -> some View {
        let active = isSessionActive(status)
        let isHotspot = status.network == .hotspot
        let tintColor = status.battery.map(PowerPalette.batteryTint) ?? .accentColor

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(snapshot.macName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isHotspot {
                    Image(systemName: "personalhotspot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PowerPalette.hotspot)
                } else if active {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: status.network.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let battery = status.battery {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(tintColor)
                    if battery.lowPowerMode == true {
                        Image(systemName: "leaf.fill").font(.caption).foregroundStyle(PowerPalette.lowPower)
                    } else if battery.isCharging {
                        Image(systemName: "bolt.fill").font(.caption).foregroundStyle(PowerPalette.charging)
                    } else if battery.onAdapter {
                        Image(systemName: "powerplug.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(isHotspot ? status.networkDisplayLabel() : batterySubtitle(battery))
                    .font(.caption2)
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let session = status.session, let deadline = session.deadline, deadline > entry.date {
                let range = min(session.startedAt, deadline)...deadline
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(session.mode.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        Text(timerInterval: range, countsDown: true)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 58, alignment: .trailing)
                    }
                    ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                }
            } else if let session = status.session, session.deadline == nil {
                HStack(spacing: 4) {
                    Label("Awake ∞", systemImage: "cup.and.saucer.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(session.startedAt, style: .timer)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 54, alignment: .trailing)
                }
            } else if showsControls && snapshot.reachable {
                Button(intent: StartKeepAwakeLiveIntent()) {
                    Label("Keep Awake 1h", systemImage: "cup.and.saucer")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isHotspot ? PowerPalette.hotspot : .accentColor)
                .controlSize(.mini)
            } else {
                Text(snapshot.reachable ? String(localized: "Can sleep") : String(localized: "Offline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let isHotspot = status.network == .hotspot
        let tintColor = status.battery.map(PowerPalette.batteryTint) ?? .accentColor

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(snapshot.macName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if status.battery?.lowPowerMode == true {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                            .foregroundStyle(PowerPalette.lowPower)
                    }
                }

                if let battery = status.battery {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(battery.percent)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(tintColor)
                        if battery.isCharging {
                            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(PowerPalette.charging)
                        } else if battery.onAdapter {
                            Image(systemName: "powerplug.fill").font(.caption).foregroundStyle(.secondary)
                        }
                        if let watts = battery.watts, abs(watts) >= 0.5 {
                            Text(watts > 0 ? "+\(Int(watts.rounded()))W" : "\(Int(watts.rounded()))W")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(batterySubtitle(battery))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Label(status.networkDisplayLabel(), systemImage: status.network.symbol)
                        .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
                    if let closed = status.lidClosed {
                        Label(closed ? String(localized: "Closed") : String(localized: "Open"),
                              systemImage: closed ? "laptopcomputer.slash" : "laptopcomputer")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let session = status.session, let deadline = session.deadline, deadline > entry.date {
                    let range = min(session.startedAt, deadline)...deadline
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(.orange)
                        Text(session.mode.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                    Spacer(minLength: 0)
                    Button(intent: StopKeepAwakeLiveIntent()) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                } else if let session = status.session, session.deadline == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                            .foregroundStyle(.orange)
                        Text(session.mode.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text(session.startedAt, style: .timer)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("Until turned off")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(intent: StopKeepAwakeLiveIntent()) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                } else {
                    Label(isHotspot ? String(localized: "Hotspot Paired") : String(localized: "Keep Awake"),
                          systemImage: isHotspot ? "personalhotspot" : "moon.zzz")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
                    Text(isHotspot
                         ? String(localized: "Ready for closed-lid in a bag.")
                         : String(localized: "Mac can sleep normally."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(intent: StartKeepAwakeLiveIntent()) {
                        Label("Keep Awake 1h", systemImage: "cup.and.saucer.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isHotspot ? PowerPalette.hotspot : .accentColor)
                    .controlSize(.small)
                    .disabled(!snapshot.reachable)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func isSessionActive(_ status: RemoteStatus) -> Bool {
        guard let session = status.session else { return false }
        if let deadline = session.deadline { return deadline > entry.date }
        return true
    }

    private func batterySubtitle(_ battery: RemoteStatus.Battery?) -> String {
        guard let battery else { return String(localized: "Desktop Mac") }
        if battery.lowPowerMode == true {
            if let m = battery.minutesRemaining, m > 0 {
                return String(localized: "Low Power · \(DurationLabel.long(minutes: m))")
            }
            return String(localized: "Low Power Mode")
        }
        if battery.isCharging {
            if let m = battery.minutesRemaining, m > 0 {
                return String(localized: "Charging · \(DurationLabel.long(minutes: m))")
            }
            return String(localized: "Charging")
        }
        if battery.onAdapter {
            if let w = battery.adapterWatts {
                return String(localized: "On \(w)W adapter")
            }
            return String(localized: "On power adapter")
        }
        if let m = battery.minutesRemaining, m > 0 {
            return String(localized: "\(DurationLabel.long(minutes: m)) remaining")
        }
        return String(localized: "On battery")
    }
}

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
            // Row 1: Full Mac Name on Left + Power/Battery Capsule on Right (never truncates Mac name)
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

            // Row 2: Keep Awake Mode & Lid State on Left + Right-Aligned Timer on Right
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

            // Row 3: Session Origin on Left + Interactive Orange Stop Button on Right
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
