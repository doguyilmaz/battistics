import ActivityKit
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
            status: .init(machineName: "MacBook Pro", readAt: .now,
                          battery: .init(percent: 76, isCharging: false, onAdapter: false, minutesRemaining: 290),
                          network: .wifi),
            lastSeen: .now, reachable: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (MacEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MacEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacEntry>) -> Void) {
        let entry = MacEntry(date: .now, snapshot: .load())
        // Ending sessions change the view without new data; refresh at the deadline.
        let deadline = entry.snapshot?.status?.session?.deadline
        let next = deadline.flatMap { $0 > .now ? $0 : nil } ?? .now.addingTimeInterval(30 * 60)
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
        .description("Battery and Keep Awake for your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacEntry

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .accessoryCircular: circular(status)
            case .accessoryRectangular: rectangular(snapshot, status)
            case .systemMedium: medium(snapshot, status)
            default: small(snapshot, status)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(.tint)
                Text("Pair a Mac in Battistics Remote").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func circular(_ status: RemoteStatus) -> some View {
        Gauge(value: Double(status.battery?.percent ?? 0), in: 0...100) {
            Image(systemName: status.session == nil ? "laptopcomputer" : "cup.and.saucer.fill")
        } currentValueLabel: {
            Text(status.battery.map { "\($0.percent)" } ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.macName).font(.headline).lineLimit(1)
            if let battery = status.battery { Text("Battery \(battery.percent)%") }
            awakeLine(status).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ snapshot: SharedSnapshot, _ status: RemoteStatus, showsNetwork: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.macName).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if showsNetwork {
                    Image(systemName: status.network.symbol).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let battery = status.battery {
                Text("\(battery.percent)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(battery.percent <= 20 && !battery.onAdapter ? Color.orange : Color.primary)
            }
            awakeLine(status).font(.caption).foregroundStyle(.secondary)
            if !snapshot.reachable, let lastSeen = snapshot.lastSeen {
                Text("Last seen \(lastSeen, style: .relative)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        HStack(spacing: 16) {
            small(snapshot, status, showsNetwork: false)
            VStack(alignment: .leading, spacing: 8) {
                Label(status.network.label, systemImage: status.network.symbol)
                if let closed = status.lidClosed {
                    Label(closed ? String(localized: "Lid closed") : String(localized: "Lid open"),
                          systemImage: "laptopcomputer")
                }
                Label(status.thermal.label, systemImage: "thermometer.medium")
                    .foregroundStyle(status.thermal.tint)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func awakeLine(_ status: RemoteStatus) -> some View {
        if let deadline = status.session?.deadline, deadline > entry.date {
            Text("Awake · \(deadline, style: .timer)")
        } else if let session = status.session, session.deadline == nil {
            Text("Kept awake")
        } else {
            Text("Can sleep")
        }
    }
}

struct KeepAwakeActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KeepAwakeActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.macName).font(.headline)
                    Text(context.state.mode.label).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: Date.now...context.state.deadline, countsDown: true)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.macName, systemImage: "laptopcomputer").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let percent = context.state.batteryPercent {
                        Text("\(percent)%").font(.caption).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.startedAt...context.state.deadline, countsDown: true) {
                        Text(context.state.mode.label).font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.tint)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.deadline, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.tint)
            }
        }
    }
}
