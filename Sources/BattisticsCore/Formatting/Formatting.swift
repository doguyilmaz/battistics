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

/// Numbers follow `Locale.current`, which inside the app is the app's
/// language with the Mac's region: Turkish gets "34,5" and "%84". Words come
/// from the app's catalog; `bundle: .main` is the app at run time, and this
/// package has no catalog of its own.
public enum Formatting {
    public static func temperature(
        _ celsius: Double, unit: TemperatureUnit, locale: Locale = .current
    ) -> String {
        let c = decimal(celsius, digits: 1, locale) + "°C"
        let f = decimal(celsius * 9 / 5 + 32, digits: 1, locale) + "°F"
        switch unit {
        case .both: return "\(c) / \(f)"
        case .celsius: return c
        case .fahrenheit: return f
        }
    }

    /// "2h 14m" style, used in detail rows.
    public static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return String(localized: "\(hours)h \(mins)m", bundle: .main) }
        return String(localized: "\(mins)m", bundle: .main)
    }

    /// "2:14" style, used in the menu bar.
    public static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func mAh(_ value: Int, locale: Locale = .current) -> String {
        "\(value.formatted(.number.locale(locale))) mAh"
    }

    public static func watts(_ value: Double, signed: Bool = false, locale: Locale = .current) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(locale)
        return value.formatted(signed ? style.sign(strategy: .always()) : style) + " W"
    }

    public static func volts(millivolts: Int, locale: Locale = .current) -> String {
        decimal(Double(millivolts) / 1000, digits: 2, locale) + " V"
    }

    public static func milliamps(_ value: Int, locale: Locale = .current) -> String {
        "\(value.formatted(.number.locale(locale))) mA"
    }

    public static func percent(_ value: Double, locale: Locale = .current) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    public static func percentPrecise(_ value: Double, locale: Locale = .current) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    /// Battery age as "4.7 years" or "8 months" under one year.
    public static func age(from date: Date, to now: Date = Date(), locale: Locale = .current) -> String {
        let years = now.timeIntervalSince(date) / (365.25 * 24 * 3600)
        if years >= 1 {
            return String(localized: "\(decimal(years, digits: 1, locale)) years", bundle: .main)
        }
        let months = max(Int((years * 12).rounded()), 1)
        return months == 1
            ? String(localized: "1 month", bundle: .main)
            : String(localized: "\(months) months", bundle: .main)
    }

    private static func decimal(_ value: Double, digits: Int, _ locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }
}
