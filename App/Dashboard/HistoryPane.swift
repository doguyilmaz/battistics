import BattisticsCore
import Charts
import SwiftUI

enum HistoryTab: String, CaseIterable, Identifiable {
    case charge
    case power
    case temperature
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charge: "Charge"
        case .power: "Power"
        case .temperature: "Temperature"
        case .health: "Health"
        }
    }

    var color: Color {
        switch self {
        case .charge: .green
        case .power: .orange
        case .temperature: .pink
        case .health: .blue
        }
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    var bucketSeconds: Int {
        switch self {
        case .day: 600
        case .week: 3600
        case .month: 3 * 3600
        case .year: 24 * 3600
        }
    }
}

struct HistoryPane: View {
    @Environment(AppModel.self) private var model
    @State private var tab: HistoryTab = .charge
    @State private var range: HistoryRange = .day
    @State private var anchor = Date()
    @State private var points: [SeriesPoint] = []
    @State private var healthPoints: [HealthPoint] = []
    @State private var totals: TimeTotals?
    @State private var selectedDate: Date?

    private var interval: DateInterval {
        Calendar.current.dateInterval(of: range.component, for: anchor)
            ?? DateInterval(start: anchor, duration: 86400)
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Metric", selection: $tab) {
                ForEach(HistoryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab != .health {
                navigationRow
            }

            GlassCard(cornerRadius: 14) {
                chartContent
                    .frame(minHeight: 260)
            }

            if tab == .charge, let totals {
                totalsRow(totals)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .navigationTitle("History")
        .task(id: loadKey) { await load() }
    }

    private var loadKey: String {
        "\(tab.rawValue)|\(range.rawValue)|\(interval.start.timeIntervalSince1970)"
    }

    private var navigationRow: some View {
        HStack(spacing: 12) {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Text(periodLabel)
                .font(.headline)
                .frame(minWidth: 170)
            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(interval.end > Date())
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    @ViewBuilder private var chartContent: some View {
        if tab == .health {
            if healthPoints.count > 1 {
                healthChart
            } else {
                emptyState("Health snapshots are recorded once per day. Come back tomorrow.")
            }
        } else if points.count > 1 {
            seriesChart
        } else {
            emptyState("Not enough data in this period yet. Battistics records as it runs.")
        }
    }

    private var seriesChart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value(tab.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tab.color.opacity(0.32), tab.color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(tab.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tab.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selected = nearestPoint {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value(tab.title, selected.value)
                )
                .foregroundStyle(tab.color)
                .annotation(
                    position: .top,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    VStack(spacing: 1) {
                        Text(valueLabel(selected.value))
                            .font(.caption.weight(.semibold))
                        Text(selected.date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: interval.start...interval.end)
        .chartXSelection(value: $selectedDate)
    }

    private var healthChart: some View {
        Chart(healthPoints) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Health", point.healthPercent)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tab.color)
            .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(
                x: .value("Date", point.date),
                y: .value("Health", point.healthPercent)
            )
            .foregroundStyle(tab.color)
            .symbolSize(24)
        }
        .chartYScale(domain: healthDomain)
    }

    private func totalsRow(_ totals: TimeTotals) -> some View {
        HStack(spacing: 24) {
            totalItem("On Battery", seconds: totals.onBattery, color: .red)
            totalItem("Charging", seconds: totals.charging, color: .yellow)
            totalItem("Fully Charged", seconds: totals.fullyCharged, color: .green)
            Spacer()
        }
    }

    private func totalItem(_ label: String, seconds: TimeInterval, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatting.duration(minutes: Int(seconds / 60)))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        ContentUnavailableView(
            "No data yet", systemImage: "chart.line.downtrend.xyaxis", description: Text(message)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func load() async {
        selectedDate = nil
        switch tab {
        case .charge:
            points = await model.history.chargeSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds)
            totals = await model.history.timeTotals(from: interval.start, to: interval.end)
        case .power:
            points = await model.history.powerSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds)
            totals = nil
        case .temperature:
            points = await model.history.temperatureSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds)
            totals = nil
        case .health:
            healthPoints = await model.history.healthSeries()
            totals = nil
        }
    }

    private func shift(by direction: Int) {
        if let shifted = Calendar.current.date(byAdding: range.component, value: direction, to: anchor) {
            anchor = shifted
        }
    }

    private var nearestPoint: SeriesPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var yDomain: ClosedRange<Double> {
        switch tab {
        case .charge: return 0...100
        case .power, .temperature:
            let maxValue = points.map(\.value).max() ?? 10
            return 0...(maxValue * 1.2 + 1)
        case .health: return healthDomain
        }
    }

    private var healthDomain: ClosedRange<Double> {
        let minValue = healthPoints.map(\.healthPercent).min() ?? 80
        return (max(minValue - 3, 0))...100
    }

    private func valueLabel(_ value: Double) -> String {
        switch tab {
        case .charge: "\(Int(value.rounded()))%"
        case .power: Formatting.watts(value)
        case .temperature: Formatting.temperature(value, unit: .celsius)
        case .health: Formatting.percentPrecise(value)
        }
    }

    private var periodLabel: String {
        switch range {
        case .day:
            return anchor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week:
            let start = interval.start.formatted(.dateTime.month(.abbreviated).day())
            let end = interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
            return "\(start) – \(end)"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .year:
            return anchor.formatted(.dateTime.year())
        }
    }
}
