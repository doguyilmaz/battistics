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
        AllMacsWidget()
        KeepAwakeActivityWidget()
        if #available(iOS 18.0, *) {
            KeepAwakeControl()
        }
    }
}

/// Each placed control starts its own mode and duration, chosen by editing it
/// in Control Center, so one can be "1 hour" and another "Lid closed, until off".
@available(iOS 18.0, *)
struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "mac.keepawake.control", provider: Provider()) { value in
            ControlWidgetToggle("Keep Mac Awake", isOn: value.isOn,
                                action: SetKeepAwakeIntent(mode: value.mode, duration: value.duration)) { on in
                Label(on ? String(localized: "Awake") : value.summary,
                      systemImage: on ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
            .tint(.orange)
        }
        .displayName("Keep Mac Awake")
        .description("Keeps the Mac you picked in Battistics Remote awake, in the mode and for the time you choose.")
    }

    struct Value {
        var isOn: Bool
        var mode: KeepAwakeMode
        var duration: KeepAwakeDuration

        /// "Lid Closed · 1 hour", what turning the control on will do.
        var summary: String {
            let time = duration == .untilOff ? String(localized: "Until turned off") : DurationLabel.long(minutes: duration.rawValue)
            return mode == .displayMaySleep ? time : "\(mode.mode.label) · \(time)"
        }
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: KeepAwakeControlConfiguration) -> Value {
            Value(isOn: false, mode: configuration.mode, duration: configuration.duration)
        }

        func currentValue(configuration: KeepAwakeControlConfiguration) async throws -> Value {
            let snapshot = SharedSnapshot.load()?.asOf(.now)
            let on = snapshot?.reachable == true && snapshot?.status?.session?.isActive(at: .now) == true
            return Value(isOn: on, mode: configuration.mode, duration: configuration.duration)
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

struct AllMacsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllMacsEntry {
        AllMacsEntry(date: .now, snapshots: [.sample()])
    }

    func getSnapshot(in context: Context, completion: @escaping (AllMacsEntry) -> Void) {
        let snapshots = SharedSnapshot.loadAll()
        completion(AllMacsEntry(date: .now, snapshots: snapshots.isEmpty ? [.sample()] : snapshots))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllMacsEntry>) -> Void) {
        let now = Date.now
        let snapshots = SharedSnapshot.loadAll()
        // Each Mac that stops writing turns offline at its own moment.
        let offline = snapshots.compactMap { $0.reachable ? $0.status?.unheardDate : nil }.filter { $0 > now }
        let entries = ([now] + offline.sorted()).map { AllMacsEntry(date: $0, snapshots: snapshots) }
        let deadline = snapshots.compactMap { $0.status?.session?.deadline }.filter { $0 > now }.min()
        completion(Timeline(entries: entries, policy: .after(deadline ?? now.addingTimeInterval(15 * 60))))
    }
}

struct AllMacsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AllMacsEntry.kind, provider: AllMacsProvider()) { entry in
            AllMacsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("All Macs")
        .description("Battery and Keep Awake for every Mac on your Apple Account.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}
