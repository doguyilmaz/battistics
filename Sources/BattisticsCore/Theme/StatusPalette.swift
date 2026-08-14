import Foundation

/// What the menu bar icon is signalling, independent of how it is drawn.
public enum BatteryStatusLevel: String, Sendable, CaseIterable {
    case neutral
    case critical
    case low
    case full
    case charging
}

/// Which status colors the user has switched on.
public struct StatusColorRules: Sendable, Equatable {
    public var colorLow: Bool
    public var lowThreshold: Int
    public var colorHigh: Bool
    public var colorCharging: Bool

    public init(colorLow: Bool, lowThreshold: Int, colorHigh: Bool, colorCharging: Bool) {
        self.colorLow = colorLow
        self.lowThreshold = lowThreshold
        self.colorHigh = colorHigh
        self.colorCharging = colorCharging
    }
}

/// Status color policy, kept out of the drawing code so it can be tested.
///
/// One fixed color per level, not a light/dark pair: the menu bar is
/// translucent over an arbitrary wallpaper, so a color that only works on
/// one backdrop is not good enough anyway. Each is picked to clear 3:1
/// against both white and black, which is what `StatusPaletteTests`
/// enforces.
public enum StatusPalette {
    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        fileprivate init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }
    }

    /// Charge at or above which "green when full" applies.
    public static let fullThreshold = 95
    /// Charge at or below which low becomes critical.
    public static let criticalThreshold = 10

    public static func level(
        percent: Int, charging: Bool, external: Bool, rules: StatusColorRules
    ) -> BatteryStatusLevel {
        if rules.colorCharging, charging { return .charging }
        if rules.colorLow, !external {
            if percent <= criticalThreshold { return .critical }
            if percent <= rules.lowThreshold { return .low }
        }
        if rules.colorHigh, percent >= fullThreshold { return .full }
        return .neutral
    }

    /// `nil` for `.neutral`, which renders as a template so macOS itself
    /// picks the color the menu bar needs.
    ///
    /// Contrast against white / black, which is what a translucent menu bar
    /// puts behind these:
    ///
    ///     red     #FF3B30   3.55 / 5.92   stock
    ///     orange  #FF9500   2.20 / 9.55   stock, weak on a light menu bar
    ///     green   #248A3D   4.40 / 4.78   deepened from #28CD41 (2.12 / 9.90)
    ///     blue    #007AFF   4.02 / 5.23   stock, already the best balanced
    ///
    /// Only green is changed. Blue measures better as it ships than any
    /// brighter variant does: raising it helps the dark menu bar and costs
    /// the light one, and #007AFF already sits near the luminance that
    /// balances both.
    public static func rgb(for level: BatteryStatusLevel) -> RGB? {
        switch level {
        case .neutral: nil
        case .critical: RGB(hex: 0xFF3B_30)
        case .low: RGB(hex: 0xFF95_00)
        case .full: RGB(hex: 0x248A_3D)
        case .charging: RGB(hex: 0x007A_FF)
        }
    }
}
