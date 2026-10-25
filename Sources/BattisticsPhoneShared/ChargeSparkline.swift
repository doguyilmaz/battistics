import BattisticsRemote
import Charts
import SwiftUI

/// Charge over the last day on a fixed 24-hour axis, so a short history
/// reads as recent rather than stretched across the day.
struct ChargeSparkline: View {
    let points: [RemoteStatus.ChargePoint]
    let tint: Color
    /// Nil grows to the space it is given.
    var height: CGFloat? = 48
    var showsLabels = true

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
            .frame(minHeight: height ?? 48, maxHeight: height ?? .infinity)
            if showsLabels {
                HStack {
                    Text("24 hours ago")
                    Spacer()
                    Text("Now")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge over the last 24 hours"))
        .accessibilityValue(Text("From \(Int(points.first?.percent ?? 0))% to \(Int(points.last?.percent ?? 0))%"))
    }
}
