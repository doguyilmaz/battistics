import AppIntents
import BattisticsRemote
import SwiftUI
import WidgetKit

/// Shared by the widget extension and the app's widget settings previews.
struct MacEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
    let prefs: WidgetPreferences

    var relevance: TimelineEntryRelevance? { snapshot.map { TimelineEntryRelevance(score: $0.relevance(at: date)) } }
}

extension SharedSnapshot {
    /// Lifts a widget in a Smart Stack: a running session most, then a battery
    /// at the level the Mac warns at.
    func relevance(at date: Date) -> Float {
        guard reachable, let status else { return 0 }
        if status.session?.isActive(at: date) == true { return 1 }
        if let battery = status.battery, !battery.onAdapter,
           battery.percent <= (status.protection.warnAtPercent ?? 20) { return 0.5 }
        return 0
    }

    static func sample() -> SharedSnapshot {
        let name = SharedSnapshot.load()?.macName ?? "MacBook Pro"
        return SharedSnapshot(
            macName: name,
            status: .init(
                machineName: name, readAt: .now,
                battery: .init(percent: 86, isCharging: true, onAdapter: true, minutesRemaining: 35,
                               healthPercent: 88, lowPowerMode: false, lowPowerPolicy: .onlyOnBattery,
                               watts: 42, adapterWatts: 67, temperatureC: 31.4, cycleCount: 115,
                               currentCapacityMah: 4230, maxCapacityMah: 4920, designCapacityMah: 5712),
                network: .wifi, networkName: "Home", lidClosed: false),
            reachable: true)
    }
}

/// Counts down a timed session, holding at zero past the deadline, and up for an open-ended one.
struct SessionTimerText: View {
    let session: RemoteStatus.Session

    var body: some View { Self.text(session) }

    static func text(_ session: RemoteStatus.Session) -> Text {
        if let range = session.countdownRange {
            Text(timerInterval: range, countsDown: true)
        } else {
            Text(session.startedAt, style: .timer)
        }
    }
}

/// Stop while a session runs, with 30 more minutes when there is room;
/// otherwise a one-hour start.
struct KeepAwakeIntentButton: View {
    let running: Bool
    let reachable: Bool
    var addsTime = false

    var body: some View {
        if running {
            HStack(spacing: 6) {
                if addsTime {
                    Button(intent: ExtendKeepAwakeLiveIntent(macID: nil, minutes: 30)) {
                        Label("30 min", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .accessibilityLabel(Text("Add 30 minutes"))
                }
                Button(intent: StopKeepAwakeLiveIntent()) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.orange)
            }
            .disabled(!reachable)
        } else {
            Button(intent: StartKeepAwakeLiveIntent()) {
                Label("Awake 1h", systemImage: "cup.and.saucer.fill").frame(maxWidth: .infinity)
            }
            .accessibilityLabel(Text("Keep Awake for 1 hour"))
            .disabled(!reachable)
        }
    }
}

enum WidgetHelpers {
    @ViewBuilder
    static func powerIcon(_ battery: RemoteStatus.Battery) -> some View {
        if battery.lowPowerMode == true {
            Image(systemName: "leaf.fill").foregroundStyle(PowerPalette.lowPower)
        } else if battery.isCharging {
            Image(systemName: "bolt.fill").foregroundStyle(PowerPalette.charging)
        } else if battery.onAdapter {
            Image(systemName: "powerplug.fill").foregroundStyle(.secondary)
        }
    }

    static func subtitle(_ battery: RemoteStatus.Battery) -> String {
        if battery.lowPowerMode == true, let time = battery.timeText {
            return String(localized: "Low Power · \(time)")
        }
        return battery.timeText ?? battery.headline
    }

    static func healthText(_ battery: RemoteStatus.Battery) -> Text? {
        battery.healthPercent.map {
            Text("\(Image(systemName: "heart.fill")) \($0)%").accessibilityLabel(Text("Health \($0)%"))
        }
    }

    static func cyclesText(_ battery: RemoteStatus.Battery) -> Text? {
        battery.cycleCount.map {
            Text("\(Image(systemName: "arrow.triangle.2.circlepath")) \($0)").accessibilityLabel(Text("\($0) cycles"))
        }
    }

    /// The short facts a widget shows next to the charge, chosen in widget settings.
    static func tokens(_ battery: RemoteStatus.Battery, _ status: RemoteStatus, prefs: WidgetPreferences) -> [Text] {
        var items: [Text?]
        switch prefs.metricFocus {
        case .powerAndHealth:
            items = [battery.powerText.map(Text.init), healthText(battery), cyclesText(battery),
                     battery.temperatureText.map(Text.init)]
        case .capacityAndCycles:
            items = [battery.currentCapacityMah.map { Text("\($0) mAh") }, cyclesText(battery), healthText(battery)]
        case .networkAndSession:
            let network = prefs.showNetworkSSID ? (status.resolvedNetworkName() ?? status.network.label) : status.network.label
            items = [Text("\(Image(systemName: status.network.symbol)) \(network)"),
                     battery.lowPowerPolicy.map { Text($0.compactBadge) }, battery.powerText.map(Text.init)]
        }
        return items.compactMap { $0 }
    }

    /// As many tokens as fit, dropping from the end instead of truncating.
    static func tokenRow(_ tokens: [Text], chips: Bool = true) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(1, tokens.count)).reversed(), id: \.self) { count in
                HStack(spacing: 4) {
                    ForEach(Array(tokens.prefix(count).enumerated()), id: \.offset) { _, token in
                        token
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, chips ? 6 : 0)
                            .padding(.vertical, chips ? 3 : 0)
                            .background(chips ? Color.secondary.opacity(0.14) : .clear, in: .rect(cornerRadius: 6))
                    }
                }
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
    }

    /// Network capsule that drops the name before it would ever truncate.
    static func networkBadge(_ status: RemoteStatus, showName: Bool) -> some View {
        let isHotspot = status.network == .hotspot
        let name = showName ? status.resolvedNetworkName() : nil
        return ViewThatFits(in: .horizontal) {
            if let name { Label(name, systemImage: status.network.symbol).fixedSize() }
            Label(status.network.label, systemImage: status.network.symbol).fixedSize()
            Image(systemName: status.network.symbol)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isHotspot ? PowerPalette.hotspot : Color.secondary).opacity(0.14), in: .capsule)
    }

    static func metricBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    static func metricBoxes(_ battery: RemoteStatus.Battery, _ status: RemoteStatus) -> some View {
        HStack(spacing: 5) {
            metricBox(String(localized: "Power"), battery.powerText ?? "–")
            metricBox(String(localized: "Health"), battery.healthPercent.map { $0.percentText } ?? "–")
            metricBox(String(localized: "Cycles"), battery.cycleCount.map(String.init) ?? "–")
            metricBox(status.thermal.label, battery.temperatureText ?? "–")
        }
    }
}
