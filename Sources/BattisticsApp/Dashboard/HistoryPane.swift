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
        case .health: String(localized: "Health")
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
    @State private var selectedDate: Date?
    @State private var chart = ChartData()
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    private var temperatureUnit: TemperatureUnit {
        (TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both).forScale
    }

    /// Everything the chart draws, swapped in a single assignment.
    ///
    /// These were eight separate `@State` values, and every glitch in this
    /// pane lived in the gaps between them: a tab's colour with the previous
    /// tab's numbers, one metric's domain scaling another's data. The charge
    /// tab needs two queries, so it committed its points and then suspended
    /// on the second — rendering values up to 100 against the domain the
    /// previous tab had left behind, which drew its area far above the card.
    ///
    /// Nothing here is guarded or sequenced. A partial update is simply not
    /// expressible: the view reads one value, and `load` publishes one value.
    struct ChartData: Equatable {
        var tab: HistoryTab = .charge
        var key = ""
        var points: [SeriesPoint] = []
        var healthPoints: [HealthPoint] = []
        /// 7-day rolling median of the daily readings. The raw series swings
        /// several points on gauge re-estimation alone, which reads as a
        /// sawtooth rather than the slow decline it is meant to show.
        var trend: [SeriesPoint] = []
        var totals: TimeTotals?
        /// Computed on load, not per body: SwiftUI re-evaluates on every
        /// hover, and rescanning the series each time is wasted work.
        var domain: ClosedRange<Double> = 0...100
        /// Carried with the points because they are already converted into
        /// it. Reading the preference at draw time instead would label a
        /// Celsius series in Fahrenheit for the frame between the two.
        var temperatureUnit: TemperatureUnit = .celsius
    }

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

            // Always laid out. Hiding it on the Health tab moved everything
            // below by its whole height every time that tab was selected.
            navigationRow
                .opacity(tab == .health ? 0 : 1)
                .disabled(tab == .health)

            GlassCard(cornerRadius: 14) {
                // A minimum, not a fixed height: the chart shares the leftover
                // space with the Spacer below and is much taller than 260.
                // Pinning it handed all of that to the Spacer and shrank every
                // chart. Uniform tab geometry is what makes the sizes match,
                // not a fixed number.
                chartContent
                    .frame(maxWidth: .infinity, minHeight: 260)
                    // Swift Charts does not clip marks to the plot rect, so a
                    // value outside the current domain is drawn wherever the
                    // scale puts it — over the picker, or over the sidebar.
                    // The atomic `ChartData` is what stops that happening;
                    // this is the guarantee that a future transition, a
                    // cancelled load or an implicit animation cannot make it
                    // happen again. The hover annotation already resolves its
                    // overflow against `.chart`, so nothing wanted is cut.
                    .clipped()
            }

            footnoteStrip
            Spacer(minLength: 0)
        }
        .padding(20)
        .navigationTitle("History")
        .task(id: loadKey) { await load() }
    }

    private var loadKey: String {
        "\(tab.rawValue)|\(range.rawValue)|\(interval.start.timeIntervalSince1970)|\(temperatureUnit.rawValue)"
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
        if chart.tab == .health {
            if chart.healthPoints.count > 1 {
                healthChart
            } else {
                emptyState("Health snapshots are recorded once per day. Come back tomorrow.")
            }
        } else if chart.points.count > 1 {
            seriesChart
        } else {
            emptyState("Not enough data in this period yet. Battistics records as it runs.")
        }
    }

    /// One reserved strip for whatever a tab adds underneath its chart, so no
    /// tab is taller than another and nothing moves when data lands.
    ///
    /// Its height is the tallest real footnote rather than a number, laid out
    /// hidden. A literal would drift the moment a font, a string or a
    /// translation changed, and drifting is the whole bug: the charge tab has
    /// always carried a totals row, so reserving exactly that keeps the chart
    /// size that tab already had and brings every other tab up to it.
    private var footnoteStrip: some View {
        ZStack(alignment: .topLeading) {
            totalsRow(TimeTotals()).hidden()
            healthCaption.hidden()
            footnote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var healthCaption: some View {
        // One literal, not a concatenation: `Text("a" + "b")` resolves to
        // the StringProtocol overload and skips localization entirely.
        Text("Dots are daily readings, the line is a 7-day trend. The controller re-estimates capacity constantly, so single days swing.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    /// Whatever the rendered tab explains underneath its chart.
    @ViewBuilder private var footnote: some View {
        if chart.tab == .charge, let totals = chart.totals {
            totalsRow(totals)
        } else if chart.tab == .health, chart.healthPoints.count > 1 {
            healthCaption
        }
    }

    private var seriesChart: some View {
        Chart {
            ForEach(chart.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value(chart.tab.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [chart.tab.color.opacity(0.32), chart.tab.color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(chart.tab.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(chart.tab.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selected = nearestPoint {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value(chart.tab.title, selected.value)
                )
                .foregroundStyle(chart.tab.color)
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
        .chartYScale(domain: chart.domain)
        .chartXScale(domain: interval.start...interval.end)
        .chartXSelection(value: $selectedDate)
    }

    private var healthChart: some View {
        Chart {
            // Raw dailies stay visible but recede; the trend carries the line.
            ForEach(chart.healthPoints) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Health", point.displayHealthPercent)
                )
                .foregroundStyle(chart.tab.color.opacity(0.28))
                .symbolSize(16)
            }
            ForEach(chart.trend) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(chart.tab.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selected = nearestHealthPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("Health", selected.displayHealthPercent)
                )
                .foregroundStyle(chart.tab.color)
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
        .chartYScale(domain: chart.domain)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func load() async {
        selectedDate = nil
        // Built locally and published in one assignment at the end. Assigning
        // to `chart` field by field would reintroduce exactly the torn frames
        // this type exists to prevent, because every `await` below is a point
        // at which SwiftUI renders whatever has been committed so far.
        var next = ChartData(tab: tab, key: loadKey)
        next.temperatureUnit = temperatureUnit
        switch tab {
        case .charge:
            next.points = await model.history.chargeSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds)
            next.totals = await model.history.timeTotals(from: interval.start, to: interval.end)
            next.domain = 0...100
        case .power:
            next.points = await model.history.powerSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds)
            // Zero is a real reading for watts, and how near a draw comes to
            // it is the point of the chart.
            next.domain = 0...((next.points.map(\.value).max() ?? 10) * 1.2 + 1)
        case .temperature:
            next.points = await model.history.temperatureSeries(
                from: interval.start, to: interval.end, bucketSeconds: range.bucketSeconds
            ).map { SeriesPoint(date: $0.date, value: temperatureUnit.convert($0.value)) }
            // Zero is not. A battery sits in a narrow band well above it, so
            // a zero-based axis squeezed a whole day into the top fifth of
            // the chart and filled the rest with a solid block.
            let values = next.points.map(\.value)
            next.domain = ((values.min() ?? 20) - 2).rounded(.down)...((values.max() ?? 40) + 2)
                .rounded(.up)
        case .health:
            next.healthPoints = await model.history.healthSeries()
            let smoothed = BatteryHealth.rollingMedian(
                next.healthPoints.map(\.displayHealthPercent), window: 7)
            next.trend = zip(next.healthPoints, smoothed).map {
                SeriesPoint(date: $0.date, value: $1)
            }
            let minValue = next.healthPoints.map(\.displayHealthPercent).min() ?? 80
            next.domain = max((minValue - 2).rounded(.down), 0)...100
        }
        chart = next
    }

    private func shift(by direction: Int) {
        if let shifted = Calendar.current.date(byAdding: range.component, value: direction, to: anchor) {
            anchor = shifted
        }
    }

    private var nearestPoint: SeriesPoint? {
        guard let selectedDate, !chart.points.isEmpty else { return nil }
        return chart.points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var nearestHealthPoint: HealthPoint? {
        guard let selectedDate, !chart.healthPoints.isEmpty else { return nil }
        return chart.healthPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func valueLabel(_ value: Double) -> String {
        switch chart.tab {
        case .charge: "\(Int(value.rounded()))%"
        case .power: Formatting.watts(value)
        // Already converted on load, so this labels rather than converts.
        case .temperature: String(format: "%.1f%@", value, chart.temperatureUnit.symbol)
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
