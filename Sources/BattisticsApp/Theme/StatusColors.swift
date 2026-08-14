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

extension NSColor {
    /// nil for `.neutral`, which stays a template so macOS colors it.
    static func status(_ level: BatteryStatusLevel) -> NSColor? {
        StatusPalette.rgb(for: level)?.nsColor
    }
}

extension Color {
    /// Same palette the menu bar uses, so the icon and the app never
    /// disagree about what "low" looks like.
    static func status(_ level: BatteryStatusLevel) -> Color {
        StatusPalette.rgb(for: level)?.color ?? .primary
    }

    static var statusGood: Color { .status(.full) }
    static var statusWarn: Color { .status(.low) }
    static var statusBad: Color { .status(.critical) }
    static var statusInfo: Color { .status(.charging) }
}
