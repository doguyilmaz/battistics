import BattisticsRemote
import Charts
import SwiftUI

struct BatteryCard: View {
    let status: RemoteStatus

    var body: some View {
        if let battery = status.battery {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Gauge(value: Double(battery.percent), in: 0...100) {
                    Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100")
                } currentValueLabel: {
                    Text("\(battery.percent)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .contentTransition(.numericText(value: Double(battery.percent)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint(battery))
                .scaleEffect(1.25)
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(battery)).font(.headline)
                    if let detail = detail(battery) {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let health = battery.healthPercent {
                        Text("Health \(health)%").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if let history = status.chargeHistory, history.count > 1 {
                ChargeSparkline(points: history, tint: tint(battery))
            }
            }
            .card()
        } else {
            Label("This Mac has no battery", systemImage: "powerplug")
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private func tint(_ battery: RemoteStatus.Battery) -> Color {
        if battery.isCharging || battery.onAdapter { return .green }
        if battery.percent <= 10 { return .red }
        if battery.percent <= 20 { return .orange }
        return .accentColor
    }

    private func headline(_ battery: RemoteStatus.Battery) -> String {
        if battery.isCharging { return String(localized: "Charging") }
        if battery.onAdapter { return String(localized: "On power adapter") }
        return String(localized: "On battery")
    }

    private func detail(_ battery: RemoteStatus.Battery) -> String? {
        guard let minutes = battery.minutesRemaining else { return nil }
        let time = DurationLabel.long(minutes: minutes)
        return battery.isCharging ? String(localized: "\(time) to full") : String(localized: "About \(time) left")
    }
}

struct KeepAwakeCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let enabled: Bool
    @Binding var message: String?
    @AppStorage("lastDuration") private var minutes = 60
    @AppStorage("lastMode") private var mode = RemoteStatus.Mode.displayMaySleep
    @State private var changed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = status.session {
                running(session)
            } else {
                idle
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .disabled(!enabled || store.pending.contains(mac.id))
        .sensoryFeedback(.success, trigger: changed)
        .onChange(of: status.session == nil) { message = nil }
    }

    private func running(_ session: RemoteStatus.Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Keeping awake", systemImage: "cup.and.saucer.fill")
                    .font(.headline).foregroundStyle(.tint)
                Spacer()
                Text(session.mode.label).font(.subheadline).foregroundStyle(.secondary)
            }
            if let deadline = session.deadline, deadline > .now {
                Text(timerInterval: Date.now...deadline, countsDown: true)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                ProgressView(timerInterval: session.startedAt...deadline, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                Text("Until turned off")
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            Text([session.name, session.origin.label].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            if status.batteryRunsOutFirst, let minutes = status.battery?.minutesRemaining {
                Label("The battery lasts about \(DurationLabel.long(minutes: minutes)), less than this session",
                      systemImage: "battery.25percent")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button(role: .destructive) {
                Task { await run { await store.stop(mac) } }
            } label: {
                Text("Stop").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keep Awake is off", systemImage: "cup.and.saucer")
                    .font(.headline)
                Spacer()
                if let end = status.lastEnd {
                    Text(end.reason.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(RemoteRequest.durations, id: \.self) { value in
                    Button { minutes = value } label: {
                        Text(DurationLabel.short(value))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(value == minutes ? Color.accentColor : Color(.tertiarySystemFill),
                                        in: Capsule())
                            .foregroundStyle(value == minutes ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DurationLabel.spoken(minutes: value))
                    .accessibilityAddTraits(value == minutes ? .isSelected : [])
                }
            }
            .animation(.snappy, value: minutes)
            Picker("Mode", selection: $mode) {
                ForEach(modes, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                let chosen = modes.contains(mode) ? mode : .displayMaySleep
                Task { await run { await store.start(mac, mode: chosen, minutes: minutes) } }
            } label: {
                Text("Keep Awake for \(DurationLabel.long(minutes: minutes))").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
    let status: RemoteStatus

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            Tile(title: String(localized: "Connection"), value: status.network.label,
                 symbol: status.network.symbol, tint: status.network == .offline ? .orange : .secondary)
            if let closed = status.lidClosed {
                Tile(title: String(localized: "Lid"), value: closed ? String(localized: "Closed") : String(localized: "Open"),
                     symbol: closed ? "laptopcomputer.slash" : "laptopcomputer", tint: .secondary)
            }
            Tile(title: String(localized: "Heat"), value: status.thermal.label, symbol: "thermometer.medium",
                 tint: status.thermal.tint)
            Tile(title: String(localized: "Battery stop"),
                 value: status.protection.stopAtPercent.map { String(localized: "At \($0)%") } ?? String(localized: "Off"),
                 symbol: "shield.lefthalf.filled", tint: .secondary)
        }
    }

    private struct Tile: View {
        let title: String
        let value: String
        let symbol: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(tint == .secondary ? Color.accentColor : tint)
                    .accessibilityHidden(true)
                Text(value).font(.headline).foregroundStyle(tint == .secondary ? Color.primary : tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
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
                .foregroundStyle(tint.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge over the last 24 hours"))
        .accessibilityValue(Text("From \(Int(points.first?.percent ?? 0))% to \(Int(points.last?.percent ?? 0))%"))
    }
}
