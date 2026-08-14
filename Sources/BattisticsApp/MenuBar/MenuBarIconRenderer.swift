import AppKit
import BattisticsCore

struct MenuBarConfig: Equatable {
    var iconStyle = MenuBarIconStyle.bat
    var showGlyph = true
    var primaryText = MenuBarText.chargePercent
    var secondaryText = MenuBarText.none
    var colorLow = true
    var lowThreshold = 20
    var colorHigh = false
    var colorCharging = false
    var temperatureUnit = TemperatureUnit.both

    var colorRules: StatusColorRules {
        StatusColorRules(
            colorLow: colorLow, lowThreshold: lowThreshold,
            colorHigh: colorHigh, colorCharging: colorCharging)
    }
}

/// MenuBarExtra labels ignore SwiftUI foreground styles (the system renders
/// them as templates), so the whole label is one composite NSImage: glyph
/// plus attributed text. Template when monochrome, tinted image when a
/// color rule applies. Images are cached per state.
@MainActor
enum MenuBarIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()
    private static let height: CGFloat = 18
    private static let glyphSize = NSSize(width: 27, height: 17)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    /// The menu bar follows the *system* appearance, which the app's own
    /// theme preference does not change. `NSApp.effectiveAppearance` reflects
    /// `preferredColorScheme` and would report the wrong backdrop whenever
    /// the two differ, so read NSGlobalDomain instead.
    static var menuBarIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Called when the system flips light/dark: every tinted image was
    /// rasterized for the old backdrop.
    static func invalidateCache() {
        cache.removeAllObjects()
    }

    static func image(snapshot: BatterySnapshot?, config: MenuBarConfig) -> NSImage {
        let dark = menuBarIsDark
        // No battery (desktop Macs, read failure): neutral empty template
        // glyph, never a red zero.
        guard let snapshot, snapshot.batteryInstalled else {
            return cachedRender(
                key: "no-battery|\(config.iconStyle.rawValue)", percent: nil, charging: false,
                texts: [], showGlyph: true, level: .neutral, shape: config.iconStyle, dark: dark)
        }
        let percent = snapshot.percent
        let charging = snapshot.isCharging
        let texts = [config.primaryText, config.secondaryText]
            .compactMap { text(for: $0, snapshot: snapshot, unit: config.temperatureUnit) }
        let level = StatusPalette.level(
            percent: percent, charging: charging, external: snapshot.externalConnected,
            rules: config.colorRules)

        // Appearance belongs in the key: a tinted image is rasterized for one
        // backdrop and is wrong for the other.
        let key = """
            \(percent)|\(charging)|\(config.showGlyph)|\(config.iconStyle.rawValue)\
            |\(texts.joined(separator: "·"))|\(level.rawValue)|\(dark ? "dark" : "light")
            """
        return cachedRender(
            key: key, percent: percent, charging: charging, texts: texts,
            showGlyph: config.showGlyph, level: level, shape: config.iconStyle, dark: dark)
    }

    private static func cachedRender(
        key: String, percent: Int?, charging: Bool, texts: [String], showGlyph: Bool,
        level: BatteryStatusLevel, shape: MenuBarIconStyle, dark: Bool
    ) -> NSImage {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image = render(
            percent: percent, charging: charging, texts: texts,
            showGlyph: showGlyph, level: level, shape: shape, dark: dark)
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private static func text(for kind: MenuBarText, snapshot: BatterySnapshot?, unit: TemperatureUnit) -> String? {
        guard let snapshot else { return nil }
        switch kind {
        case .none:
            return nil
        case .chargePercent:
            return "\(snapshot.percent)%"
        case .healthPercent:
            return "H\(Int(snapshot.displayHealthPercent.rounded()))%"
        case .timeRemaining:
            guard let minutes = snapshot.timeRemainingMin else { return nil }
            return Formatting.clock(minutes: minutes)
        case .temperature:
            guard let celsius = snapshot.temperatureC else { return nil }
            let value = unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
            return "\(Int(value.rounded()))°"
        case .watts:
            guard let watts = snapshot.watts else { return nil }
            return String(format: "%.1fW", abs(watts))
        case .currentmAh:
            return "\(snapshot.rawCurrentCapacity)"
        }
    }

    private static func render(
        percent: Int?, charging: Bool, texts: [String], showGlyph: Bool,
        level: BatteryStatusLevel, shape: MenuBarIconStyle, dark: Bool
    ) -> NSImage {
        let tint = StatusPalette.rgb(for: level, dark: dark)?.nsColor
        let isTemplate = tint == nil
        // A template image carries alpha only and macOS colors it for the
        // menu bar. Once a status tint applies we lose that, so the outline
        // and the text have to take the menu bar's own label color by hand —
        // tinting the text is what made it unreadable over a wallpaper.
        let outline: NSColor = isTemplate ? .black : (dark ? .white : .black)
        let string = texts.joined(separator: " ")
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: outline]
        let textSize = string.isEmpty ? .zero : (string as NSString).size(withAttributes: attributes)

        var width: CGFloat = 0
        if showGlyph { width += glyphSize.width }
        if showGlyph && !string.isEmpty { width += 4 }
        width += ceil(textSize.width)
        if width == 0 { width = glyphSize.width }

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            if showGlyph || string.isEmpty {
                let glyphRect = NSRect(
                    x: 0, y: (height - glyphSize.height) / 2,
                    width: glyphSize.width, height: glyphSize.height)
                BatGlyph.draw(
                    in: glyphRect,
                    style: BatGlyph.Style(
                        color: outline, fillColor: tint, charging: charging,
                        fillFraction: percent.map { CGFloat($0) / 100 },
                        shape: shape))
                x += glyphSize.width + 4
            }
            if !string.isEmpty {
                (string as NSString).draw(
                    at: NSPoint(x: x, y: (height - textSize.height) / 2 + 0.5),
                    withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
}
