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
/// The menu bar is translucent over whatever wallpaper the user picked, so a
/// tint has to hold up against both a light and a dark backdrop. `NSColor`'s
/// system colors are tuned for opaque app surfaces and sit at mid luminance:
/// `.systemGreen` and `.systemOrange` fall under 3:1 against a light menu bar
/// and visibly wash out. These are Apple's own higher-contrast variants of the
/// same hues, chosen per appearance.
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
    public static func rgb(for level: BatteryStatusLevel, dark: Bool) -> RGB? {
        switch level {
        case .neutral: nil
        case .critical: RGB(hex: dark ? 0xFF69_61 : 0xD700_15)
        case .low: RGB(hex: dark ? 0xFFB3_40 : 0xC934_00)
        case .full: RGB(hex: dark ? 0x30DB_5B : 0x248A_3D)
        case .charging: RGB(hex: dark ? 0x409C_FF : 0x0040_DD)
        }
    }
}
