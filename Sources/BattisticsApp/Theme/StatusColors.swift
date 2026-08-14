import AppKit
import BattisticsCore
import SwiftUI

extension StatusPalette.RGB {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

extension Color {
    /// A light/dark pair resolved against the view's appearance. Used where
    /// a single system color would be too low-contrast in one of the two.
    static func adaptive(light: StatusPalette.RGB, dark: StatusPalette.RGB) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? dark.nsColor : light.nsColor
            })
    }

    /// Status hue for an arbitrary level, matching the menu bar exactly so
    /// the icon and the app never disagree about what "low" looks like.
    static func status(_ level: BatteryStatusLevel) -> Color {
        guard let light = StatusPalette.rgb(for: level, dark: false),
            let dark = StatusPalette.rgb(for: level, dark: true)
        else { return .primary }
        return .adaptive(light: light, dark: dark)
    }

    // Semantic aliases. SwiftUI's `.green` and `.orange` are the same
    // mid-luminance system colors that fail against a light background, so
    // the app draws from the menu bar palette rather than from them.
    static var statusGood: Color { .status(.full) }
    static var statusWarn: Color { .status(.low) }
    static var statusBad: Color { .status(.critical) }
    static var statusInfo: Color { .status(.charging) }
}
