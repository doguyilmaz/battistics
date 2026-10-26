import BattisticsRemote
import SwiftUI
import WidgetKit

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    /// The timeline reloads at a deadline with the same snapshot, so an ended session is judged here.
    private func activeSession(_ status: RemoteStatus) -> RemoteStatus.Session? {
        status.session.flatMap { $0.isActive(at: entry.date) ? $0 : nil }
    }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .systemMedium: medium(snapshot, status)
            case .systemLarge: large(snapshot, status)
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

    private func header(_ snapshot: SharedSnapshot, font: Font) -> some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.reachable ? "laptopcomputer" : "laptopcomputer.slash")
                .foregroundStyle(.secondary)
            Text(snapshot.macName)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 4)
        }
        .font(font)
    }

    private func charge(_ battery: RemoteStatus.Battery, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(battery.percent)%")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(PowerPalette.batteryTint(battery))
                .minimumScaleFactor(0.8)
            WidgetHelpers.powerIcon(battery).font(.caption)
        }
    }

    private func small(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(snapshot, font: .caption.weight(.bold))
            if let battery = status.battery {
                charge(battery, size: 30)
                Text(WidgetHelpers.subtitle(battery))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let session = activeSession(status), snapshot.reachable {
                HStack {
                    Label(session.mode.label, systemImage: session.deadline == nil ? "infinity" : session.mode.symbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    SessionTimerText(session: session).monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 60, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            } else if snapshot.reachable {
                KeepAwakeIntentButton(running: false, reachable: true)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Label("Offline", systemImage: "wifi.slash")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header(snapshot, font: .subheadline.weight(.bold))
                WidgetHelpers.networkBadge(status, showName: entry.prefs.showNetworkSSID)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let battery = status.battery {
                        charge(battery, size: 32)
                        Text(WidgetHelpers.subtitle(battery))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        WidgetHelpers.tokenRow(WidgetHelpers.tokens(battery, status, prefs: entry.prefs))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                sessionPanel(snapshot, status)
                    .frame(width: 128)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func sessionPanel(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let session = activeSession(status) {
                Label(session.mode.label, systemImage: session.deadline == nil ? "infinity" : session.mode.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                SessionTimerText(session: session)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Label(snapshot.bagReady ? String(localized: "Bag Ready") : String(localized: "Idle"),
                      systemImage: snapshot.bagReady ? "personalhotspot" : "moon.zzz.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.bagReady ? PowerPalette.hotspot : .secondary)
                    .lineLimit(1)
                Text(snapshot.reachable ? String(localized: "Mac can sleep") : String(localized: "Offline"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            KeepAwakeIntentButton(running: activeSession(status) != nil, reachable: snapshot.reachable)
                .font(.caption2.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func large(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header(snapshot, font: .headline)
                WidgetHelpers.networkBadge(status, showName: entry.prefs.showNetworkSSID)
            }
            if let battery = status.battery {
                HStack(spacing: 12) {
                    Gauge(value: Double(battery.percent), in: 0...100) {
                        Image(systemName: battery.symbol)
                    } currentValueLabel: {
                        Text("\(battery.percent)").font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(PowerPalette.batteryTint(battery))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(battery.headline).font(.subheadline.weight(.semibold))
                        Text(WidgetHelpers.subtitle(battery))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let lid = status.lidClosed {
                            Text(lid ? String(localized: "Lid closed") : String(localized: "Lid open"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                WidgetHelpers.metricBoxes(battery, status)
            }
            if let points = status.chargeHistory, points.count > 1 {
                ChargeSparkline(points: points, tint: status.battery.map(PowerPalette.batteryTint) ?? .accentColor,
                                height: 54, showsLabels: false)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let session = activeSession(status) {
                        Label(session.mode.label, systemImage: session.deadline == nil ? "infinity" : session.mode.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        SessionTimerText(session: session)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .frame(maxWidth: 90, alignment: .leading)
                    } else {
                        Text(snapshot.bagReady ? String(localized: "Bag Ready") : String(localized: "Keep Awake is off"))
                            .font(.caption.weight(.semibold))
                        Text(snapshot.bagReady ? String(localized: "On Hotspot, safe to close the lid") : String(localized: "Mac can sleep normally"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 4)
                KeepAwakeIntentButton(running: activeSession(status) != nil, reachable: snapshot.reachable,
                                      addsTime: activeSession(status)?.deadline != nil)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacTelemetryWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status, let battery = status.battery {
            let tint = snapshot.reachable ? PowerPalette.batteryTint(battery) : .secondary
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if !snapshot.reachable {
                        Image(systemName: "laptopcomputer.slash").font(.caption2.weight(.bold))
                    }
                    Text(snapshot.macName)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    if family == .systemMedium, let current = battery.currentCapacityMah, let full = battery.maxCapacityMah {
                        Text("\(current) / \(full) mAh")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(battery.percent)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                        Text(snapshot.reachable ? WidgetHelpers.subtitle(battery) : String(localized: "Offline"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    if family == .systemMedium, let points = status.chargeHistory, points.count > 1 {
                        ChargeSparkline(points: points, tint: tint, height: 44, showsLabels: false)
                    }
                }
                Spacer(minLength: 0)
                if family == .systemMedium {
                    WidgetHelpers.metricBoxes(battery, status)
                } else {
                    HStack(spacing: 4) {
                        WidgetHelpers.metricBox(String(localized: "Power"), battery.powerText ?? "–")
                        WidgetHelpers.metricBox(String(localized: "Health"), battery.healthPercent.map { $0.percentText } ?? "–")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.macName).font(.caption.weight(.bold)).lineLimit(1)
                Label("This Mac has no battery", systemImage: "powerplug").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Open Battistics Remote").font(.caption)
        }
    }
}

struct AllMacsEntry: TimelineEntry {
    static let kind = "mac.all"
    let date: Date
    let snapshots: [SharedSnapshot]

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: snapshots.map { $0.relevance(at: date) }.max() ?? 0)
    }
}

/// One row per Mac: charge, or the Keep Awake countdown while one runs.
struct AllMacsWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: AllMacsEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if entry.snapshots.isEmpty {
            Text("Open Battistics Remote").font(.caption)
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(entry.snapshots.prefix(3).enumerated()), id: \.offset) { _, snapshot in
                    AllMacsLine(snapshot: snapshot.asOf(entry.date), date: entry.date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 7) {
                ForEach(Array(entry.snapshots.prefix(family == .systemLarge ? 7 : 3).enumerated()), id: \.offset) { _, snapshot in
                    if let url = snapshot.url {
                        Link(destination: url) { AllMacsRow(snapshot: snapshot.asOf(entry.date), date: entry.date) }
                    } else {
                        AllMacsRow(snapshot: snapshot.asOf(entry.date), date: entry.date)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .systemLarge ? .topLeading : .leading)
        }
    }
}

/// One Lock Screen line: symbol, name and charge.
private struct AllMacsLine: View {
    let snapshot: SharedSnapshot
    let date: Date

    var body: some View {
        let running = snapshot.reachable && snapshot.status?.session?.isActive(at: date) == true
        HStack(spacing: 4) {
            Image(systemName: !snapshot.reachable ? "laptopcomputer.slash"
                  : running ? "cup.and.saucer.fill" : (snapshot.status?.macSymbol ?? "laptopcomputer"))
                .frame(width: 16)
            Text(snapshot.macName).lineLimit(1)
            Spacer(minLength: 2)
            Text(snapshot.status?.battery.map { "\($0.percent)%" } ?? "–")
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
    }
}

private struct AllMacsRow: View {
    let snapshot: SharedSnapshot
    let date: Date

    var body: some View {
        let battery = snapshot.status?.battery
        let session = snapshot.reachable ? snapshot.status?.session.flatMap { $0.isActive(at: date) ? $0 : nil } : nil
        let tint = snapshot.reachable ? battery.map(PowerPalette.batteryTint) ?? .accentColor : .secondary
        HStack(spacing: 10) {
            Image(systemName: snapshot.reachable ? (snapshot.status?.macSymbol ?? "laptopcomputer") : "laptopcomputer.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.macName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if !snapshot.reachable {
                        Text("Offline")
                    } else if let session {
                        HStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                            SessionTimerText(session: session)
                        }
                        .foregroundStyle(.orange)
                    } else if let battery {
                        Text(WidgetHelpers.subtitle(battery))
                    } else {
                        Text("This Mac has no battery")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let battery {
                Text("\(battery.percent)%")
                    .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
            }
        }
    }
}
