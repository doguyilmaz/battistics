import AppIntents
import BattisticsRemote
import SwiftUI
import WidgetKit

/// Shared by the widget extension and the app's widget gallery, so the gallery
/// renders the exact same views at the exact same sizes the system uses.
struct MacEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
    let prefs: WidgetPreferences
}

extension SharedSnapshot {
    static func sample(named name: String? = nil) -> SharedSnapshot {
        let macName = name ?? SharedSnapshot.load()?.macName ?? "MacBook Pro"
        return SharedSnapshot(
            macName: macName,
            status: .init(
                machineName: macName,
                readAt: .now,
                battery: .init(
                    percent: 86, isCharging: true, onAdapter: true, minutesRemaining: 35,
                    healthPercent: 88, lowPowerMode: false, lowPowerPolicy: .onlyOnBattery,
                    watts: 42, adapterWatts: 67, temperatureC: 31.4, cycleCount: 115,
                    designCycleCount: 1000, currentCapacityMah: 4230, maxCapacityMah: 4920,
                    rawMaxCapacityMah: 4895, designCapacityMah: 5712, voltageMV: 12450, amperageMA: 3370
                ),
                network: .wifi,
                networkName: "Home",
                lidClosed: false,
                thermal: .nominal,
                macModel: "MacBook Pro 14\""
            ),
            reachable: true
        )
    }
}

// MARK: - Mac Dashboard widget

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .accessoryInline:
                LockScreenWidgets.inline(snapshot: snapshot, status: status, now: entry.date)
            case .accessoryCircular:
                LockScreenWidgets.circular(status: status, now: entry.date)
            case .accessoryRectangular:
                if entry.prefs.lockScreenLayout == .detailedGrid {
                    LockScreenWidgets.detailedRectangular(snapshot: snapshot, status: status, prefs: entry.prefs, now: entry.date)
                } else {
                    LockScreenWidgets.cleanRectangular(snapshot: snapshot, status: status, prefs: entry.prefs, now: entry.date)
                }
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

    // MARK: Small

    private func small(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let active = WidgetHelpers.isSessionActive(status, now: entry.date)
        let isHotspot = status.network == .hotspot
        let tint = status.battery.map(PowerPalette.batteryTint) ?? .accentColor

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isHotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
                Text(snapshot.macName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "cup.and.saucer.fill").font(.caption2).foregroundStyle(.orange)
                }
            }

            if let battery = status.battery {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.8)
                    WidgetHelpers.powerIcon(battery)
                        .font(.caption2)
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    Text(WidgetHelpers.compactHealthLine(battery, includePower: true))
                    Text(WidgetHelpers.compactHealthLine(battery, includePower: false))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let session = status.session, let deadline = session.deadline, deadline > entry.date {
                let range = min(session.startedAt, deadline)...deadline
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(session.mode.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Text(timerInterval: range, countsDown: true)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .foregroundStyle(.orange)
                    ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                }
            } else if let session = status.session, session.deadline == nil {
                HStack(spacing: 4) {
                    Label("Awake ∞", systemImage: "cup.and.saucer.fill")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    Text(session.startedAt, style: .timer)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 54, alignment: .trailing)
                }
                .foregroundStyle(.orange)
            } else if snapshot.reachable {
                Button(intent: StartKeepAwakeLiveIntent()) {
                    Label("Awake 1h", systemImage: "cup.and.saucer.fill")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isHotspot ? PowerPalette.hotspot : .accentColor)
                .controlSize(.small)
            } else {
                Text("Offline")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private func medium(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let isHotspot = status.network == .hotspot
        let tint = status.battery.map(PowerPalette.batteryTint) ?? .accentColor

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isHotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : Color.accentColor)
                Text(snapshot.macName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(2)
                Spacer(minLength: 4)
                WidgetHelpers.networkBadge(status, showName: entry.prefs.showNetworkSSID)
                    .layoutPriority(1)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    if let battery = status.battery {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(battery.percent)%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            WidgetHelpers.powerIcon(battery).font(.caption)
                        }
                        Text(WidgetHelpers.shortBatterySubtitle(battery))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        WidgetHelpers.tokenRow(WidgetHelpers.telemetryTokens(battery: battery, status: status, focus: entry.prefs.metricFocus))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                sessionPanel(snapshot, status, isHotspot: isHotspot)
                    .frame(width: 128)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sessionPanel(_ snapshot: SharedSnapshot, _ status: RemoteStatus, isHotspot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let session = status.session {
                Label(session.mode.label, systemImage: session.deadline == nil ? "infinity" : session.mode.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Group {
                    if let deadline = session.deadline, deadline > entry.date {
                        Text(timerInterval: min(session.startedAt, deadline)...deadline, countsDown: true)
                    } else {
                        Text(session.startedAt, style: .timer)
                    }
                }
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Button(intent: StopKeepAwakeLiveIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            } else {
                Label(snapshot.bagReady ? String(localized: "Bag Ready") : String(localized: "Idle"),
                      systemImage: snapshot.bagReady ? "handbag.fill" : "moon.zzz.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.bagReady ? PowerPalette.hotspot : .secondary)
                    .lineLimit(1)
                Text(snapshot.bagReady ? String(localized: "On Hotspot") : String(localized: "Mac can sleep"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(intent: StartKeepAwakeLiveIntent()) {
                    Label("Awake 1h", systemImage: "cup.and.saucer.fill")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isHotspot ? PowerPalette.hotspot : .accentColor)
                .controlSize(.small)
                .disabled(!snapshot.reachable)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Large

    private func large(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let isHotspot = status.network == .hotspot
        let tint = status.battery.map(PowerPalette.batteryTint) ?? .accentColor

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isHotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.macName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(status.macModel ?? "Mac")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(2)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    WidgetHelpers.networkBadge(status, showName: entry.prefs.showNetworkSSID)
                    if let closed = status.lidClosed {
                        Text(closed ? String(localized: "Lid Closed") : String(localized: "Lid Open"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let battery = status.battery {
                HStack(spacing: 12) {
                    Gauge(value: Double(battery.percent), in: 0...100) {
                        Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100")
                    } currentValueLabel: {
                        Text("\(battery.percent)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(WidgetHelpers.shortBatterySubtitle(battery))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let cur = battery.currentCapacityMah, let maxCap = battery.maxCapacityMah {
                            Text("\(cur) / \(maxCap) mAh")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let policy = battery.lowPowerPolicy {
                            Label(policy.label, systemImage: policy.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    WidgetHelpers.metricBox(String(localized: "Power"), WidgetHelpers.powerText(battery))
                    WidgetHelpers.metricBox(String(localized: "Health"), battery.healthPercent.map { "\($0)%" } ?? "-")
                    WidgetHelpers.metricBox(String(localized: "Cycles"), battery.cycleCount.map { "\($0)" } ?? "-")
                    WidgetHelpers.metricBox(String(localized: "Temp"), battery.temperatureC.map { "\(Int($0.rounded()))°C" } ?? status.thermal.label)
                }
            }

            if let points = status.chargeHistory, points.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last 24 hours")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    WidgetSparkline(points: points, tint: tint)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let session = status.session {
                        Text(session.deadline == nil ? "∞ · \(session.mode.label)" : session.mode.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        Group {
                            if let deadline = session.deadline, deadline > entry.date {
                                Text(timerInterval: min(session.startedAt, deadline)...deadline, countsDown: true)
                            } else {
                                Text(session.startedAt, style: .timer)
                            }
                        }
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                    } else {
                        Text(snapshot.bagReady ? String(localized: "Bag Ready") : String(localized: "Keep Awake is off"))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(snapshot.bagReady ? String(localized: "On Hotspot, safe to close the lid") : String(localized: "Mac can sleep normally"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 4)
                if status.session != nil {
                    Button(intent: StopKeepAwakeLiveIntent()) {
                        Label("Stop", systemImage: "stop.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                } else {
                    Button(intent: StartKeepAwakeLiveIntent()) {
                        Label("Awake 1h", systemImage: "cup.and.saucer.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isHotspot ? PowerPalette.hotspot : .accentColor)
                    .controlSize(.small)
                    .disabled(!snapshot.reachable)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Battery Telemetry widget

struct MacTelemetryWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status, let battery = status.battery {
            let tint = PowerPalette.batteryTint(battery)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label(snapshot.macName, systemImage: "laptopcomputer")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        if let cur = battery.currentCapacityMah, let maxCap = battery.maxCapacityMah {
                            Text("\(cur) / \(maxCap) mAh")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(battery.percent)%")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            Text(WidgetHelpers.shortBatterySubtitle(battery))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(width: 100, alignment: .leading)
                        if let points = status.chargeHistory, points.count > 1 {
                            WidgetSparkline(points: points, tint: tint)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    HStack(spacing: 5) {
                        WidgetHelpers.metricBox(String(localized: "Power"), WidgetHelpers.powerText(battery))
                        WidgetHelpers.metricBox(String(localized: "Health"), battery.healthPercent.map { "\($0)%" } ?? "-")
                        WidgetHelpers.metricBox(String(localized: "Cycles"), battery.cycleCount.map { "\($0)" } ?? "-")
                        WidgetHelpers.metricBox(String(localized: "Temp"), battery.temperatureC.map { "\(Int($0.rounded()))°C" } ?? status.thermal.label)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.macName)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(battery.percent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    if let cur = battery.currentCapacityMah {
                        Text("\(cur) mAh")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        WidgetHelpers.metricBox(String(localized: "Power"), WidgetHelpers.powerText(battery))
                        WidgetHelpers.metricBox(String(localized: "Health"), battery.healthPercent.map { "\($0)%" } ?? "-")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            Text("Open Battistics Remote").font(.caption)
        }
    }
}

// MARK: - Lock Screen widgets

struct MacLockScreenDetailView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .accessoryInline:
                LockScreenWidgets.inline(snapshot: snapshot, status: status, now: entry.date)
            case .accessoryCircular:
                LockScreenWidgets.circular(status: status, now: entry.date)
            default:
                if entry.prefs.lockScreenLayout == .detailedGrid {
                    LockScreenWidgets.detailedRectangular(snapshot: snapshot, status: status, prefs: entry.prefs, now: entry.date)
                } else {
                    LockScreenWidgets.cleanRectangular(snapshot: snapshot, status: status, prefs: entry.prefs, now: entry.date)
                }
            }
        } else {
            Text("Battistics").font(.caption)
        }
    }
}

enum LockScreenWidgets {
    @ViewBuilder
    static func inline(snapshot: SharedSnapshot, status: RemoteStatus, now: Date) -> some View {
        let percent = status.battery.map { "\($0.percent)%" } ?? "-"
        if let session = status.session, let deadline = session.deadline, deadline > now {
            Label {
                Text("\(percent) · \(Text(timerInterval: min(session.startedAt, deadline)...deadline, countsDown: true))")
            } icon: {
                Image(systemName: "cup.and.saucer.fill")
            }
        } else if status.session != nil {
            Label("\(percent) · Awake ∞", systemImage: "cup.and.saucer.fill")
        } else if let battery = status.battery {
            Label("Mac \(percent) · \(WidgetHelpers.powerText(battery))",
                  systemImage: battery.isCharging ? "bolt.fill" : "laptopcomputer")
        } else {
            Label(snapshot.macName, systemImage: "laptopcomputer")
        }
    }

    static func circular(status: RemoteStatus, now: Date) -> some View {
        let symbol: String = {
            if WidgetHelpers.isSessionActive(status, now: now) { return "cup.and.saucer.fill" }
            if status.battery?.lowPowerMode == true { return "leaf.fill" }
            if status.battery?.isCharging == true { return "bolt.fill" }
            if status.network == .hotspot { return "personalhotspot" }
            return "laptopcomputer"
        }()
        return Gauge(value: Double(status.battery?.percent ?? 0), in: 0...100) {
            Image(systemName: symbol)
        } currentValueLabel: {
            Text(status.battery.map { "\($0.percent)" } ?? "-")
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    /// Fills the whole rectangular slot: name and charge, a full-width bar,
    /// then telemetry or the session timer. Every row falls back to a shorter
    /// form instead of truncating.
    static func detailedRectangular(snapshot: SharedSnapshot, status: RemoteStatus, prefs: WidgetPreferences, now: Date) -> some View {
        let battery = status.battery
        let active = WidgetHelpers.isSessionActive(status, now: now)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: status.network == .hotspot ? "personalhotspot" : (active ? "cup.and.saucer.fill" : "laptopcomputer"))
                    .font(.system(size: 11, weight: .bold))
                Text(snapshot.macName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let battery {
                    HStack(spacing: 2) {
                        WidgetHelpers.powerIcon(battery).font(.system(size: 10, weight: .bold))
                        Text("\(battery.percent)%")
                            .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    }
                    .fixedSize()
                }
            }

            if let session = status.session, let deadline = session.deadline, deadline > now {
                ProgressView(timerInterval: min(session.startedAt, deadline)...deadline, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                Gauge(value: Double(battery?.percent ?? 0), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }

            if let session = status.session {
                HStack(spacing: 4) {
                    Text(session.deadline == nil ? "∞ \(session.mode.label)" : session.mode.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    Group {
                        if let deadline = session.deadline, deadline > now {
                            Text(timerInterval: min(session.startedAt, deadline)...deadline, countsDown: true)
                        } else {
                            Text(session.startedAt, style: .timer)
                        }
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58, alignment: .trailing)
                }
            } else if let battery {
                ViewThatFits(in: .horizontal) {
                    telemetryLine(battery, status, prefs: prefs, items: 3)
                    telemetryLine(battery, status, prefs: prefs, items: 2)
                    telemetryLine(battery, status, prefs: prefs, items: 1)
                }
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static func telemetryLine(_ battery: RemoteStatus.Battery, _ status: RemoteStatus, prefs: WidgetPreferences, items: Int) -> some View {
        var parts: [String] = []
        switch prefs.metricFocus {
        case .powerAndHealth:
            parts.append(WidgetHelpers.powerText(battery))
            if let health = battery.healthPercent { parts.append("♥\(health)%") }
            if let cycles = battery.cycleCount { parts.append("\(cycles)c") }
            else if let temp = battery.temperatureC { parts.append("\(Int(temp.rounded()))°") }
        case .capacityAndCycles:
            if let cur = battery.currentCapacityMah, let maxCap = battery.maxCapacityMah {
                parts.append("\(cur)/\(maxCap)mAh")
            } else {
                parts.append(WidgetHelpers.powerText(battery))
            }
            if let cycles = battery.cycleCount { parts.append("\(cycles)c") }
            if let health = battery.healthPercent { parts.append("♥\(health)%") }
        case .networkAndSession:
            let net = prefs.showNetworkSSID ? status.networkDisplayLabel() : status.network.label
            parts.append(net)
            if let policy = battery.lowPowerPolicy { parts.append(policy.compactBadge) }
            parts.append(WidgetHelpers.powerText(battery))
        }
        return HStack(spacing: 0) {
            ForEach(Array(parts.prefix(items).enumerated()), id: \.offset) { index, part in
                if index > 0 { Spacer(minLength: 6) }
                Text(part).lineLimit(1).fixedSize()
            }
        }
    }

    static func cleanRectangular(snapshot: SharedSnapshot, status: RemoteStatus, prefs: WidgetPreferences, now: Date) -> some View {
        let pct = status.battery?.percent ?? 0
        let net = prefs.showNetworkSSID ? status.networkDisplayLabel() : status.network.label
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: status.network == .hotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.system(size: 11, weight: .bold))
                Text(snapshot.macName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text("\(pct)%")
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .fixedSize()
            }
            Gauge(value: Double(pct), in: 0...100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            HStack(spacing: 4) {
                Text(net)
                if let closed = status.lidClosed {
                    Text(closed ? String(localized: "Closed") : String(localized: "Open"))
                }
                Spacer(minLength: 2)
                if let battery = status.battery {
                    Text(WidgetHelpers.powerText(battery)).fixedSize()
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

enum WidgetHelpers {
    static func isSessionActive(_ status: RemoteStatus, now: Date) -> Bool {
        guard let session = status.session else { return false }
        if let deadline = session.deadline { return deadline > now }
        return true
    }

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

    static func powerText(_ battery: RemoteStatus.Battery) -> String {
        if let watts = battery.watts, abs(watts) >= 0.5 {
            let value = Int(watts.rounded())
            return value > 0 ? "+\(value)W" : "\(value)W"
        }
        if let adapter = battery.adapterWatts { return "\(adapter)W AC" }
        return battery.onAdapter ? "AC" : String(localized: "Battery")
    }

    static func compactHealthLine(_ battery: RemoteStatus.Battery, includePower: Bool) -> String {
        var parts: [String] = []
        if includePower { parts.append(powerText(battery)) }
        if let health = battery.healthPercent { parts.append("♥\(health)%") }
        if let cycles = battery.cycleCount { parts.append("\(cycles)c") }
        return parts.joined(separator: " · ")
    }

    static func shortBatterySubtitle(_ battery: RemoteStatus.Battery) -> String {
        if battery.lowPowerMode == true {
            if let m = battery.minutesRemaining, m > 0 { return String(localized: "Low Power · \(DurationLabel.long(minutes: m))") }
            return String(localized: "Low Power")
        }
        if battery.isCharging {
            if let m = battery.minutesRemaining, m > 0 { return String(localized: "Full in \(DurationLabel.long(minutes: m))") }
            return String(localized: "Charging")
        }
        if battery.onAdapter {
            if let w = battery.adapterWatts { return String(localized: "\(w)W adapter") }
            return String(localized: "Plugged in")
        }
        if let m = battery.minutesRemaining, m > 0 { return String(localized: "\(DurationLabel.long(minutes: m)) left") }
        return String(localized: "On battery")
    }

    static func telemetryTokens(battery: RemoteStatus.Battery, status: RemoteStatus, focus: WidgetPreferences.MetricFocus) -> [String] {
        switch focus {
        case .powerAndHealth:
            var items = [powerText(battery)]
            if let h = battery.healthPercent { items.append("♥\(h)%") }
            if let c = battery.cycleCount { items.append("\(c)c") }
            if let t = battery.temperatureC { items.append("\(Int(t.rounded()))°C") }
            return items
        case .capacityAndCycles:
            var items: [String] = []
            if let cur = battery.currentCapacityMah { items.append("\(cur) mAh") }
            if let c = battery.cycleCount { items.append("\(c)c") }
            if let v = battery.voltageMV { items.append(String(format: "%.1fV", Double(v) / 1000)) }
            if items.isEmpty { items.append(powerText(battery)) }
            return items
        case .networkAndSession:
            var items = [status.network.label, powerText(battery)]
            if let policy = battery.lowPowerPolicy { items.append(policy.shortBadge) }
            return items
        }
    }

    /// Shows as many tokens as fit, dropping from the end instead of truncating.
    static func tokenRow(_ tokens: [String]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(1, tokens.count)).reversed(), id: \.self) { count in
                HStack(spacing: 4) {
                    ForEach(Array(tokens.prefix(count).enumerated()), id: \.offset) { _, token in
                        Text(token)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    /// Network capsule that drops the SSID before it would ever truncate.
    static func networkBadge(_ status: RemoteStatus, showName: Bool) -> some View {
        let isHotspot = status.network == .hotspot
        let name = showName ? status.resolvedNetworkName() : nil
        return ViewThatFits(in: .horizontal) {
            if let name {
                Label("\(status.network.label) · \(name)", systemImage: status.network.symbol).fixedSize()
                Label(name, systemImage: status.network.symbol).fixedSize()
            }
            Label(status.network.label, systemImage: status.network.symbol).fixedSize()
            Image(systemName: status.network.symbol)
        }
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(isHotspot ? PowerPalette.hotspot : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isHotspot ? PowerPalette.hotspot : Color.secondary).opacity(0.14), in: Capsule())
    }

    static func metricBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WidgetSparkline: View {
    let points: [RemoteStatus.ChargePoint]
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let line = linePath(in: geo.size)
            fillPath(from: line, in: geo.size)
                .fill(LinearGradient(colors: [tint.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
            line.stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func linePath(in size: CGSize) -> Path {
        guard let first = points.first?.at, let last = points.last?.at else { return Path() }
        let span = max(last.timeIntervalSince(first), 1)
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(point.at.timeIntervalSince(first) / span) * size.width
            let y = (1 - CGFloat(min(max(point.percent, 0), 100)) / 100) * (size.height - 4) + 2
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func fillPath(from line: Path, in size: CGSize) -> Path {
        guard !line.isEmpty else { return Path() }
        var path = line
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
