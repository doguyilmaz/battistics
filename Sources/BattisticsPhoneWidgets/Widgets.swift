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
        if #available(iOS 18.0, *) {
            KeepAwakeControl()
        }
    }
}

@available(iOS 18.0, *)
struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mac.keepawake.control", provider: Provider()) { isOn in
            ControlWidgetToggle("Keep Mac Awake", isOn: isOn, action: SetKeepAwakeIntent()) { on in
                Label(on ? String(localized: "Awake") : String(localized: "Can Sleep"),
                      systemImage: on ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
            .tint(.orange)
        }
        .displayName("Keep Mac Awake")
        .description("Keeps the Mac you picked in Battistics Remote awake for an hour.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            guard let snapshot = SharedSnapshot.load(), snapshot.reachable else { return false }
            return snapshot.status?.session?.isActive(at: .now) ?? false
        }
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
