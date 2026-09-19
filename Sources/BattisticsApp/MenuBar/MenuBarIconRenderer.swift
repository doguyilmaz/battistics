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
    /// Draws a small trailing cup while a Keep Awake session runs, so the
    /// state is visible without opening the popover. User-toggleable.
    var keepAwakeIcon = false
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

    static func image(snapshot: BatterySnapshot?, config: MenuBarConfig) -> NSImage {
        // No battery (desktop Macs, read failure): neutral empty template
        // glyph, never a red zero.
        guard let snapshot, snapshot.batteryInstalled else {
            return cachedRender(
                key: "no-battery|\(config.iconStyle.rawValue)|\(config.keepAwakeIcon)",
                percent: nil, charging: false, texts: [], showGlyph: true, tint: nil,
                shape: config.iconStyle, keepAwakeIcon: config.keepAwakeIcon)
        }
        let percent = snapshot.percent
        let charging = snapshot.isCharging
        let external = snapshot.externalConnected
        let texts = [config.primaryText, config.secondaryText]
            .compactMap { text(for: $0, snapshot: snapshot, unit: config.temperatureUnit) }
        let tint = tintColor(percent: percent, charging: charging, external: external, config: config)

        let key = "\(percent)|\(charging)|\(external)|\(config.showGlyph)|\(config.iconStyle.rawValue)|\(texts.joined(separator: "·"))|\(tint?.description ?? "template")|\(config.keepAwakeIcon)"
        return cachedRender(
            key: key, percent: percent, charging: charging, texts: texts,
            showGlyph: config.showGlyph, tint: tint, shape: config.iconStyle,
            keepAwakeIcon: config.keepAwakeIcon)
    }

    private static func cachedRender(
        key: String, percent: Int?, charging: Bool, texts: [String], showGlyph: Bool,
        tint: NSColor?, shape: MenuBarIconStyle, keepAwakeIcon: Bool
    ) -> NSImage {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image = render(
            percent: percent, charging: charging, texts: texts,
            showGlyph: showGlyph, tint: tint, shape: shape, keepAwakeIcon: keepAwakeIcon)
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Status ladder: charging blue, critical red, low orange, full green,
    /// monochrome template otherwise. Each rung is user-toggleable.
    /// Internal so the appearance settings can render true previews.
    static func tintColor(
        percent: Int, charging: Bool, external: Bool, config: MenuBarConfig
    ) -> NSColor? {
        if config.colorCharging, charging { return .systemBlue }
        if config.colorLow, !external {
            if percent <= 10 { return .systemRed }
            if percent <= config.lowThreshold { return .systemOrange }
        }
        if config.colorHigh, percent >= 95 { return .systemGreen }
        return nil
    }

    private static func text(for kind: MenuBarText, snapshot: BatterySnapshot?, unit: TemperatureUnit) -> String? {
        guard let snapshot else { return nil }
        switch kind {
        case .none:
            return nil
        case .chargePercent:
            return "\(snapshot.percent)%"
        case .healthPercent:
            guard snapshot.hasHealthReading else { return "H—" }
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

    // A cup rather than a dot: at this size a 5pt circle reads as an
    // artifact, and it cannot say what it means. The symbol is legible and
    // self-explanatory, and drawing a real glyph avoids the sub-pixel edge
    // trouble a tiny filled circle had.
    private static let awakeSymbolSize = NSSize(width: 12, height: 12)
    private static let awakeGap: CGFloat = 4
    private static let awakeTrailingPad: CGFloat = 1.5

    private static let awakeSymbol: NSImage? = {
        let image = NSImage(
            systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Keep Awake")
        return image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
    }()

    private static func render(
        percent: Int?, charging: Bool, texts: [String], showGlyph: Bool, tint: NSColor?,
        shape: MenuBarIconStyle, keepAwakeIcon: Bool
    ) -> NSImage {
        let color = tint ?? .black
        let string = texts.joined(separator: " ")
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = string.isEmpty ? .zero : (string as NSString).size(withAttributes: attributes)

        var width: CGFloat = 0
        if showGlyph { width += glyphSize.width }
        if showGlyph && !string.isEmpty { width += 4 }
        width += ceil(textSize.width)
        if width == 0 { width = glyphSize.width }
        if keepAwakeIcon { width += awakeGap + awakeSymbolSize.width + awakeTrailingPad }

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
                        color: color, charging: charging,
                        fillFraction: percent.map { CGFloat($0) / 100 },
                        shape: shape))
                x += glyphSize.width + 4
            }
            if !string.isEmpty {
                (string as NSString).draw(
                    at: NSPoint(x: x, y: (height - textSize.height) / 2 + 0.5),
                    withAttributes: attributes)
                x += ceil(textSize.width)
            }
            if keepAwakeIcon, let symbol = awakeSymbol {
                let box = NSRect(
                    x: x + awakeGap, y: (height - awakeSymbolSize.height) / 2,
                    width: awakeSymbolSize.width, height: awakeSymbolSize.height)
                symbol.draw(
                    in: box, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
                // Symbols carry their own color; sourceAtop repaints only the
                // pixels the glyph actually covers, leaving everything else
                // in the composite untouched.
                color.setFill()
                box.fill(using: .sourceAtop)
            }
            return true
        }
        image.isTemplate = tint == nil
        return image
    }
}
