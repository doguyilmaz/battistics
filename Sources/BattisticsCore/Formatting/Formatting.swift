import Foundation

public enum TemperatureUnit: String, Sendable, CaseIterable {
    case both
    case celsius
    case fahrenheit

    /// The unit an axis can actually draw.
    ///
    /// `both` is a convenience for text, where "35.0°C / 95.0°F" reads fine.
    /// A scale has one unit, so a chart resolves through this first and shows
    /// Fahrenheit only when that is the explicit choice.
    public var forScale: TemperatureUnit { self == .fahrenheit ? .fahrenheit : .celsius }

    /// Readings are stored in Celsius; a chart plots them converted, so its
    /// axis labels carry the same numbers as its values.
    public func convert(_ celsius: Double) -> Double {
        self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    public var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

public enum Formatting {
    public static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        let fahrenheit = celsius * 9 / 5 + 32
        switch unit {
        case .both:
            return String(format: "%.1f°C / %.1f°F", celsius, fahrenheit)
        case .celsius:
            return String(format: "%.1f°C", celsius)
        case .fahrenheit:
            return String(format: "%.1f°F", fahrenheit)
        }
    }

    /// "2h 14m" style, used in detail rows.
    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// "2:14" style, used in the menu bar.
    public static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func mAh(_ value: Int) -> String {
        "\(value.formatted(.number.grouping(.automatic))) mAh"
    }

    public static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    public static func volts(millivolts: Int) -> String {
        String(format: "%.2f V", Double(millivolts) / 1000)
    }

    public static func milliamps(_ value: Int) -> String {
        "\(value) mA"
    }

    public static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    public static func percentPrecise(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// Battery age as "4.7 years" or "8 months" under one year.
    public static func age(from date: Date, to now: Date = Date()) -> String {
        let years = now.timeIntervalSince(date) / (365.25 * 24 * 3600)
        if years >= 1 { return String(format: "%.1f years", years) }
        let months = max(Int((years * 12).rounded()), 1)
        return months == 1 ? "1 month" : "\(months) months"
    }
}
