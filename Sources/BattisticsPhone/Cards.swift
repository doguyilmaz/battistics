import BattisticsRemote
import Charts
import SwiftUI
import UIKit

/// Always-present bottom dock card that morphs between Unreachable, Hotspot Paired
/// (Pocket Mode), and Desk/Wi‑Fi states without shifting the layout vertically.
struct PocketModeDock: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openURL) private var openURL
    let mac: MacStore.Mac
    let reading: MacStore.Reading?
    let status: RemoteStatus
    @Binding var message: String?

    var body: some View {
        let reachable = reading?.reachable == true
        let isHotspot = reachable && status.network == .hotspot
        let isPocketMode = isHotspot && status.lidClosed == true && status.session?.mode == .lidClosed
        let hotspotName = status.resolvedNetworkName(fallbackHotspot: UIDevice.current.name)
        let canQuickStartClosedLid = reachable && status.session == nil && status.protection.closedLidAllowed

        let accent: Color = !reachable ? .orange : (isHotspot ? PowerPalette.hotspot : Color.accentColor)

        HStack(spacing: 12) {
            Image(systemName: !reachable
                  ? "antenna.radiowaves.left.and.right.slash"
                  : (isHotspot ? "personalhotspot" : "laptopcomputer.and.iphone"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative.reversing, isActive: isHotspot)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(titleText(reachable: reachable, isHotspot: isHotspot, isPocketMode: isPocketMode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(!reachable || isHotspot ? accent : .primary)
                        .lineLimit(1)
                    if isHotspot, let hotspotName {
                        Text("· \(hotspotName)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(subtitleText(reachable: reachable, isHotspot: isHotspot, isPocketMode: isPocketMode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if canQuickStartClosedLid && isHotspot {
                Button {
                    Task {
                        let failure = await store.start(mac, mode: .lidClosed, minutes: 60)
                        withAnimation { message = failure }
                    }
                } label: {
                    Label("Bag 1h", systemImage: "Briefcase.fill".lowercased() == "briefcase.fill" ? "handbag.fill" : "laptopcomputer")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(PowerPalette.hotspot)
                .controlSize(.small)
                .disabled(store.pending.contains(mac.id))
            } else {
                Button {
                    HotspotOpener.open(using: openURL)
                } label: {
                    Label("Hotspot", systemImage: "personalhotspot")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isHotspot
                      ? PowerPalette.hotspot.opacity(0.10)
                      : (!reachable ? Color.orange.opacity(0.08) : Color(.secondarySystemGroupedBackground)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isHotspot
                    ? PowerPalette.hotspot.opacity(0.45)
                    : (!reachable ? Color.orange.opacity(0.35) : Color.clear),
                    lineWidth: 1.1
                )
        )
    }

    private func titleText(reachable: Bool, isHotspot: Bool, isPocketMode: Bool) -> String {
        if !reachable {
            return String(localized: "Can’t reach \(mac.name)")
        }
        if isPocketMode {
            return String(localized: "Pocket Mode Active")
        }
        if isHotspot {
            return String(localized: "Hotspot Paired")
        }
        return String(localized: "Hotspot & Pocket Mode")
    }

    private func subtitleText(reachable: Bool, isHotspot: Bool, isPocketMode: Bool) -> String {
        if !reachable {
            return status.session != nil
                ? String(localized: "Keep Awake was running when last seen.")
                : String(localized: "Offline — open Hotspot if away from Wi‑Fi.")
        }
        if isPocketMode {
            return String(localized: "Lid closed & awake on your hotspot.")
        }
        if isHotspot {
            return String(localized: "Linked to iPhone — ready for bag mode")
        }
        return String(localized: "Ready for closed-lid bag mode")
    }
}

struct BatteryCard: View {
    let status: RemoteStatus

    var body: some View {
        if let battery = status.battery {
            let tintColor = PowerPalette.batteryTint(battery)
            let showEnergyBorder = battery.lowPowerMode == true || battery.isCharging || battery.onAdapter

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Gauge(value: Double(battery.percent), in: 0...100) {
                        Image(systemName: gaugeSymbol(battery))
                            .foregroundStyle(tintColor)
                            .symbolEffect(.pulse, isActive: battery.isCharging)
                    } currentValueLabel: {
                        Text("\(battery.percent)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .contentTransition(.numericText(value: Double(battery.percent)))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tintColor)
                    .scaleEffect(1.22)
                    .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(headline(battery))
                                .font(.headline)
                            if battery.lowPowerMode == true {
                                Label("Low Power", systemImage: "leaf.fill")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(PowerPalette.lowPower.opacity(0.18), in: Capsule())
                                    .foregroundStyle(PowerPalette.lowPower)
                            } else if battery.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PowerPalette.charging)
                                    .symbolEffect(.pulse, isActive: true)
                            }
                        }

                        if let detail = detail(battery) {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                // 3-pillar telemetry strip (Power Flow · Health · Pack Temp)
                HStack(spacing: 8) {
                    MetricPill(
                        label: String(localized: "Power"),
                        value: powerFlowLabel(battery) ?? (battery.onAdapter ? String(localized: "AC") : String(localized: "Battery")),
                        symbol: battery.isCharging || battery.onAdapter ? "bolt.fill" : "battery.75percent",
                        tint: battery.isCharging ? PowerPalette.charging : .secondary
                    )
                    MetricPill(
                        label: String(localized: "Health"),
                        value: battery.healthPercent.map { "\($0)%" } ?? "—",
                        symbol: "heart.fill",
                        tint: .secondary
                    )
                    MetricPill(
                        label: String(localized: "Temp"),
                        value: battery.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—",
                        symbol: "thermometer.medium",
                        tint: status.thermal == .nominal ? .secondary : status.thermal.tint
                    )
                }

                if let history = status.chargeHistory, history.count > 1 {
                    VStack(spacing: 4) {
                        ChargeSparkline(points: history, tint: tintColor)
                        HStack {
                            Text("24h ago")
                            Spacer()
                            Text("12h ago")
                            Spacer()
                            Text("Now")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .card(borderColor: showEnergyBorder ? tintColor.opacity(0.35) : nil)
        } else {
            Label("This Mac has no battery", systemImage: "powerplug")
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private struct MetricPill: View {
        let label: String
        let value: String
        let symbol: String
        let tint: Color

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint == .secondary ? Color.accentColor : tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func gaugeSymbol(_ battery: RemoteStatus.Battery) -> String {
        if battery.lowPowerMode == true { return "leaf.fill" }
        if battery.isCharging { return "bolt.fill" }
        if battery.onAdapter { return "powerplug.fill" }
        return "battery.100"
    }

    private func headline(_ battery: RemoteStatus.Battery) -> String {
        if battery.isCharging { return String(localized: "Charging") }
        if battery.onAdapter { return String(localized: "On power adapter") }
        return String(localized: "On battery")
    }

    private func detail(_ battery: RemoteStatus.Battery) -> String? {
        guard let minutes = battery.minutesRemaining else {
            if let adapterWatts = battery.adapterWatts {
                return String(localized: "\(adapterWatts)W power adapter")
            }
            return nil
        }
        let time = DurationLabel.long(minutes: minutes)
        return battery.isCharging ? String(localized: "\(time) to full") : String(localized: "About \(time) left")
    }

    private func powerFlowLabel(_ battery: RemoteStatus.Battery) -> String? {
        if let watts = battery.watts, abs(watts) >= 0.5 {
            let formatted = Int(watts.rounded())
            if formatted > 0 { return "+\(formatted)W" }
            return "\(formatted)W"
        }
        if let adapterWatts = battery.adapterWatts {
            return "\(adapterWatts)W"
        }
        return nil
    }
}

/// Fixed-height Keep Awake control card: switching between Idle and Running or
/// surfacing a warning/error never changes the card's vertical size, preventing
/// any layout shift or scroll jump.
struct KeepAwakeCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let enabled: Bool
    @Binding var message: String?
    /// `0` means "Until turned off" (indefinite), selected by tapping the active pill to deselect it.
    @AppStorage("lastDuration") private var minutes = 60
    @AppStorage("lastMode") private var mode = RemoteStatus.Mode.displayMaySleep
    @State private var changed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
                .frame(height: 22)

            ZStack {
                if let session = status.session {
                    runningBody(session)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    idleControls
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(height: 76)

            feedbackLine
                .frame(height: 18)

            actionButton
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(borderColor: status.session != nil ? Color.orange.opacity(0.45) : nil)
        .disabled(!enabled || store.pending.contains(mac.id))
        .sensoryFeedback(.success, trigger: changed)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: status.session != nil)
        .onChange(of: status.session == nil) { message = nil }
    }

    @ViewBuilder
    private var headerRow: some View {
        if let session = status.session {
            HStack {
                Label("Keeping awake", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)
                Spacer()
                Label(session.mode.label, systemImage: session.mode.symbol)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        } else {
            HStack {
                Label("Keep Awake is off", systemImage: "cup.and.saucer")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        minutes = (minutes == 0) ? 60 : 0
                    }
                } label: {
                    if minutes == 0 {
                        Label("Until turned off", systemImage: "infinity")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    } else if let end = status.lastEnd {
                        Text(end.reason.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap selected time for ∞")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runningBody(_ session: RemoteStatus.Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deadline = session.deadline, deadline > .now {
                let range = min(session.startedAt, deadline)...deadline
                HStack(alignment: .firstTextBaseline) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(session.origin.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.orange)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Label("Until turned off", systemImage: "infinity")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(session.startedAt, style: .timer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
                ProgressView(value: 1.0)
                    .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(RemoteRequest.durations, id: \.self) { value in
                    let isSelected = (value == minutes)
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            // 2-step toggle: tapping the active duration deselects it -> "Until turned off" (0).
                            minutes = isSelected ? 0 : value
                        }
                    } label: {
                        Text(DurationLabel.short(value))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                isSelected ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: minutes)
                    .accessibilityLabel(DurationLabel.spoken(minutes: value))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Picker("Mode", selection: $mode.animation(.snappy(duration: 0.25))) {
                ForEach(modes, id: \.self) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Fixed 18pt single-line slot that swaps smoothly between errors, battery
    /// warnings, session origin, and mode descriptions without any height change.
    @ViewBuilder
    private var feedbackLine: some View {
        if let message {
            Button {
                withAnimation { self.message = nil }
            } label: {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        } else if status.batteryRunsOutFirst, let left = status.battery?.minutesRemaining {
            Label("Battery lasts about \(DurationLabel.long(minutes: left)), less than this session",
                  systemImage: "battery.25percent")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let session = status.session {
            let distinctName = (session.name == "iPhone") ? nil : session.name
            Text([distinctName, session.origin.label].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text((modes.contains(mode) ? mode : .displayMaySleep).subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if status.session != nil {
            Button(role: .destructive) {
                Task { await run { await store.stop(mac) } }
            } label: {
                HStack(spacing: 6) {
                    if store.pending.contains(mac.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "stop.fill")
                    }
                    Text("Stop Keep Awake")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else {
            Button {
                let chosen = modes.contains(mode) ? mode : .displayMaySleep
                Task { await run { await store.start(mac, mode: chosen, minutes: minutes) } }
            } label: {
                HStack(spacing: 6) {
                    if store.pending.contains(mac.id) {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: minutes == 0 ? "infinity" : "cup.and.saucer.fill")
                    }
                    Text(minutes == 0
                         ? String(localized: "Keep Awake Until Stopped")
                         : String(localized: "Keep Awake for \(DurationLabel.long(minutes: minutes))"))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var modes: [RemoteStatus.Mode] {
        status.protection.closedLidAllowed ? [.displayMaySleep, .displayOn, .lidClosed] : [.displayMaySleep, .displayOn]
    }

    private func run(_ action: () async -> String?) async {
        let failure = await action()
        withAnimation { message = failure }
        if failure == nil { changed += 1 }
    }
}

struct ConditionsGrid: View {
    @Environment(\.openURL) private var openURL
    let status: RemoteStatus

    var body: some View {
        let networkName = status.resolvedNetworkName(fallbackHotspot: UIDevice.current.name)
        let isHotspot = status.network == .hotspot

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            Button {
                HotspotOpener.open(using: openURL)
            } label: {
                Tile(
                    title: networkName ?? String(localized: "Connection"),
                    value: status.network.label,
                    symbol: status.network.symbol,
                    tint: status.network == .offline ? .orange : (isHotspot ? PowerPalette.hotspot : .secondary),
                    highlighted: isHotspot
                )
            }
            .buttonStyle(.plain)

            Tile(
                title: status.protection.closedLidAllowed ? String(localized: "Lid · Bag ready") : String(localized: "Lid"),
                value: (status.lidClosed ?? false) ? String(localized: "Closed") : String(localized: "Open"),
                symbol: (status.lidClosed ?? false) ? "laptopcomputer.slash" : "laptopcomputer",
                tint: .secondary
            )

            Tile(
                title: status.battery?.temperatureC.map { "\(Int($0.rounded()))°C · " + String(localized: "Heat") } ?? String(localized: "Heat"),
                value: status.thermal.label,
                symbol: "thermometer.medium",
                tint: status.thermal.tint
            )

            Tile(
                title: String(localized: "Battery stop"),
                value: status.protection.stopAtPercent.map { String(localized: "At \($0)%") } ?? String(localized: "Off"),
                symbol: "shield.lefthalf.filled",
                tint: .secondary
            )
        }
    }

    private struct Tile: View {
        let title: String
        let value: String
        let symbol: String
        let tint: Color
        var highlighted: Bool = false

        var body: some View {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint == .secondary ? Color.accentColor : tint)
                    .frame(width: 32, height: 32)
                    .background((tint == .secondary ? Color.accentColor : tint).opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint == .secondary ? Color.primary : tint)
                        .lineLimit(1)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(highlighted ? PowerPalette.hotspot.opacity(0.10) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlighted ? PowerPalette.hotspot.opacity(0.4) : .clear, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

/// The Mac's charge over the last day, for a glance at the trend.
struct ChargeSparkline: View {
    let points: [RemoteStatus.ChargePoint]
    let tint: Color

    var body: some View {
        Chart(points, id: \.at) { point in
            AreaMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge over the last 24 hours"))
        .accessibilityValue(Text("From \(Int(points.first?.percent ?? 0))% to \(Int(points.last?.percent ?? 0))%"))
    }
}
