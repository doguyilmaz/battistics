import BattisticsRemote
import SwiftUI
import WidgetKit

struct MacLockScreenDetailView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MacEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot, let status = snapshot.status {
            switch family {
            case .accessoryInline: inline(status)
            case .accessoryCircular: circular(status)
            default: rectangular(snapshot, status)
            }
        } else {
            Text("Battistics").font(.caption)
        }
    }

    private var reachable: Bool { entry.snapshot?.reachable == true }

    @ViewBuilder
    private func inline(_ status: RemoteStatus) -> some View {
        let percent = status.battery.map { $0.percent.percentText } ?? "–"
        if !reachable {
            Label("Offline", systemImage: status.macSymbol(reachable: false))
        } else if let session = status.session, session.isActive(at: entry.date) {
            Label {
                Text("\(percent) · \(SessionTimerText.text(session))")
            } icon: {
                Image(systemName: "cup.and.saucer.fill")
            }
        } else if let battery = status.battery {
            Label("\(percent) · \(battery.powerText ?? battery.headline)", systemImage: battery.symbol)
        } else {
            Label(entry.snapshot?.macName ?? "Mac", systemImage: status.macSymbol)
        }
    }

    @ViewBuilder
    private func circular(_ status: RemoteStatus) -> some View {
        let symbol = !reachable ? status.macSymbol(reachable: false)
            : status.session?.isActive(at: entry.date) == true ? "cup.and.saucer.fill"
            : (status.battery?.symbol ?? status.macSymbol)
        if let battery = status.battery {
            Gauge(value: Double(battery.percent), in: 0...100) {
                Image(systemName: symbol)
            } currentValueLabel: {
                Text("\(battery.percent)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol).font(.title3.weight(.semibold))
            }
        }
    }

    /// Name and charge, a full-width bar, then the session timer or the chosen details.
    private func rectangular(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let battery = status.battery
        let session = reachable ? status.session.flatMap { $0.isActive(at: entry.date) ? $0 : nil } : nil
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: !reachable ? status.macSymbol(reachable: false) : session != nil ? "cup.and.saucer.fill" : status.network.symbol)
                    .font(.caption2.weight(.bold))
                Text(snapshot.macName)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let battery {
                    Text("\(battery.percent)%")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy).monospacedDigit())
                        .fixedSize()
                }
            }
            if let range = session?.countdownRange {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            } else if let battery {
                Gauge(value: Double(battery.percent), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            if !reachable {
                HStack(spacing: 4) {
                    Text("Offline")
                    Spacer(minLength: 2)
                    Text(status.readAt, style: .time)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            } else if let session {
                HStack(spacing: 4) {
                    Text(session.mode.label).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    SessionTimerText(session: session).multilineTextAlignment(.trailing).frame(maxWidth: 60, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
            } else if let battery {
                let tokens = entry.prefs.lockScreenLayout == .detailedGrid
                    ? WidgetHelpers.tokens(battery, status, prefs: entry.prefs)
                    : [Text(status.network.label), battery.powerText.map(Text.init) ?? Text(battery.headline)]
                WidgetHelpers.tokenRow(tokens, chips: false)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Label(status.network.label, systemImage: status.network.symbol)
                    Label(status.thermal.label, systemImage: "thermometer.medium")
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
