import BattisticsRemote
import Charts
import SwiftUI

extension View {
    func card(border: Color? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: 22).strokeBorder(border, lineWidth: 1)
                }
            }
    }

    /// iOS has no public link to Personal Hotspot settings, so this explains the path instead.
    func hotspotHelp(isPresented: Binding<Bool>) -> some View {
        alert("Turn On Personal Hotspot", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On this iPhone, open Settings › Personal Hotspot and turn on Allow Others to Join. A Mac set to join hotspots automatically connects by itself.")
        }
    }
}

/// The scrolling page every dashboard sits on.
struct DashboardPage<Content: View>: View {
    var refresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable { await refresh?() }
    }
}

/// A two-line fact in the conditions grid.
struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor
    var highlighted = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlighted ? tint.opacity(0.10) : Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.4), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small value with its label, three to a row under a battery headline.
struct MetricPill: View {
    let label: String
    let value: String
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct BatteryGauge: View {
    let percent: Int?
    let symbol: String
    let tint: Color

    var body: some View {
        Gauge(value: Double(percent ?? 0), in: 0...100) {
            Image(systemName: symbol).foregroundStyle(tint)
        } currentValueLabel: {
            Text(percent.map(String.init) ?? "–")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText(value: Double(percent ?? 0)))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(tint)
        .scaleEffect(1.2)
        .frame(width: 64, height: 64)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text(percent.map { "\($0)%" } ?? "–"))
    }
}

/// Charge over the last day on a fixed 24-hour axis, so a short history
/// reads as recent rather than stretched across the day.
struct ChargeSparkline: View {
    let points: [RemoteStatus.ChargePoint]
    let tint: Color

    var body: some View {
        let now = Date()
        VStack(spacing: 4) {
            Chart(points, id: \.at) { point in
                AreaMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXScale(domain: now.addingTimeInterval(-86_400)...now)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 48)
            HStack {
                Text("24 hours ago")
                Spacer()
                Text("Now")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge over the last 24 hours"))
        .accessibilityValue(Text("From \(Int(points.first?.percent ?? 0))% to \(Int(points.last?.percent ?? 0))%"))
    }
}
