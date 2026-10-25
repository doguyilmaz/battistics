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

    @ViewBuilder
    private func inline(_ status: RemoteStatus) -> some View {
        let percent = status.battery.map { $0.percent.percentText } ?? "–"
        if let session = status.session, session.isActive(at: entry.date) {
            Label {
                Text("\(percent) · \(SessionTimerText.text(session))")
            } icon: {
                Image(systemName: "cup.and.saucer.fill")
            }
        } else if let battery = status.battery {
            Label("\(percent) · \(battery.powerText ?? battery.headline)", systemImage: battery.symbol)
        } else {
            Label(entry.snapshot?.macName ?? "Mac", systemImage: "laptopcomputer")
        }
    }

    private func circular(_ status: RemoteStatus) -> some View {
        let symbol = WidgetHelpers.isSessionActive(status, now: entry.date)
            ? "cup.and.saucer.fill"
            : (status.battery?.symbol ?? "laptopcomputer")
        return Gauge(value: Double(status.battery?.percent ?? 0), in: 0...100) {
            Image(systemName: symbol)
        } currentValueLabel: {
            Text(status.battery.map { "\($0.percent)" } ?? "–")
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    /// Name and charge, a full-width bar, then the session timer or the chosen details.
    private func rectangular(_ snapshot: SharedSnapshot, _ status: RemoteStatus) -> some View {
        let battery = status.battery
        let session = status.session.flatMap { $0.isActive(at: entry.date) ? $0 : nil }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: session != nil ? "cup.and.saucer.fill" : status.network.symbol)
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
            } else {
                Gauge(value: Double(battery?.percent ?? 0), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            if let session {
                HStack(spacing: 4) {
                    Text(session.mode.label).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    SessionTimerText(session: session).fixedSize()
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
            } else if let battery {
                let tokens = entry.prefs.lockScreenLayout == .detailedGrid
                    ? WidgetHelpers.tokens(battery, status, prefs: entry.prefs)
                    : [Text(status.network.label), battery.powerText.map(Text.init) ?? Text(battery.headline)]
                WidgetHelpers.tokenRow(tokens, chips: false)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
