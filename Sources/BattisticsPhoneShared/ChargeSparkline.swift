import BattisticsRemote
import Charts
import SwiftUI

/// Charge over the last day on a fixed 24-hour axis, so a short history
/// reads as recent rather than stretched across the day. Dragging across it
/// in the app reads out the charge at that time; widgets cannot be touched.
struct ChargeSparkline: View {
    let points: [RemoteStatus.ChargePoint]
    let tint: Color
    /// Nil grows to the space it is given.
    var height: CGFloat? = 48
    var showsLabels = true
    @State private var selection: Date?

    var body: some View {
        let now = Date()
        let picked = selection.flatMap(nearest)
        VStack(spacing: 4) {
            Chart {
                ForEach(points, id: \.at) { point in
                    AreaMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.at), y: .value("Charge", point.percent))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let picked {
                    RuleMark(x: .value("Time", picked.at))
                        .foregroundStyle(tint.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Time", picked.at), y: .value("Charge", picked.percent))
                        .foregroundStyle(tint)
                        .symbolSize(36)
                }
            }
            .chartXScale(domain: now.addingTimeInterval(-86_400)...now)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXSelection(value: $selection)
            .sensoryFeedback(.selection, trigger: picked?.at)
            .frame(minHeight: height ?? 48, maxHeight: height ?? .infinity)
            if showsLabels {
                HStack {
                    if let picked {
                        Text(Int(picked.percent.rounded()).percentText)
                            .foregroundStyle(tint)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(picked.at, format: .dateTime.hour().minute())
                    } else {
                        Text("24 hours ago")
                        Spacer()
                        Text("Now")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge over the last 24 hours"))
        .accessibilityValue(Text("From \(Int(points.first?.percent ?? 0).percentText) to \(Int(points.last?.percent ?? 0).percentText)"))
    }

    private func nearest(_ date: Date) -> RemoteStatus.ChargePoint? {
        points.min { abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date)) }
    }
}
