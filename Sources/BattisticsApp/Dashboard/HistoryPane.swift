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
        case .charge: String(localized: "Charge")
        case .power: String(localized: "Power")
        case .temperature: String(localized: "Temperature")
        case .health: String(localized: "Capacity")
        }
    }

    var color: Color {
        switch self {
        case .charge: .statusGood
        case .power: .statusWarn
        case .temperature: .pink
        case .health: .statusInfo
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
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .year: String(localized: "Year")
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
    /// 7-day rolling median of the daily readings. The raw series swings
    /// several points on gauge re-estimation alone, which reads as a sawtooth
    /// rather than as the slow decline it is meant to show.
    @State private var healthTrendLine: [SeriesPoint] = []
    @State private var totals: TimeTotals?
    @State private var selectedDate: Date?
    // Computed once per load: SwiftUI re-evaluates body on every hover and
    // selection change, and scanning the full series each time is wasted work.
    @State private var seriesDomain: ClosedRange<Double> = 0...100
    @State private var healthDomain: ClosedRange<Double> = 80...100

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
                VStack(spacing: 6) {
                    healthChart
                    // One literal, not a concatenation: `Text("a" + "b")`
                    // resolves to the StringProtocol overload and skips
                    // localization entirely.
                    Text("Dots are daily readings, the line is a 7-day trend. The controller re-estimates capacity constantly, so single days swing.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            } else {
                emptyState("Capacity snapshots are recorded once per day. Come back tomorrow.")
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
        .chartYScale(domain: seriesDomain)
        .chartXScale(domain: interval.start...interval.end)
        .chartXSelection(value: $selectedDate)
    }

    private var healthChart: some View {
        Chart {
            // Raw dailies stay visible but recede; the trend carries the line.
            ForEach(healthPoints) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Capacity", point.displayHealthPercent)
                )
                .foregroundStyle(tab.color.opacity(0.28))
                .symbolSize(16)
            }
            ForEach(healthTrendLine) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tab.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selected = nearestHealthPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("Capacity", selected.displayHealthPercent)
                )
                .foregroundStyle(tab.color)
                .symbolSize(60)
                .annotation(
                    position: .top,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    VStack(spacing: 1) {
                        Text(Formatting.percentPrecise(selected.displayHealthPercent))
                            .font(.caption.weight(.semibold))
                        Text("\(selected.cycleCount) cycles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(selected.date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .chartYScale(domain: healthDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartXSelection(value: $selectedDate)
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
            let smoothed = BatteryHealth.rollingMedian(
                healthPoints.map(\.displayHealthPercent), window: 7)
            healthTrendLine = zip(healthPoints, smoothed).map {
                SeriesPoint(date: $0.date, value: $1)
            }
            totals = nil
        }
        recomputeDomains()
    }

    /// Health never plots above 100 (see `BatteryHealth.display`), so the top
    /// is fixed and only the floor follows the data.
    private func recomputeDomains() {
        if tab == .health {
            let minValue = healthPoints.map(\.displayHealthPercent).min() ?? 80
            healthDomain = max((minValue - 2).rounded(.down), 0)...100
        } else if tab == .charge {
            seriesDomain = 0...100
        } else {
            let maxValue = points.map(\.value).max() ?? 10
            seriesDomain = 0...(maxValue * 1.2 + 1)
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

    private var nearestHealthPoint: HealthPoint? {
        guard let selectedDate, !healthPoints.isEmpty else { return nil }
        return healthPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
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
