import AppKit
import BattisticsCore

struct MenuBarConfig: Equatable {
    var showGlyph = true
    var primaryText = MenuBarText.chargePercent
    var secondaryText = MenuBarText.none
    var colorLow = true
    var lowThreshold = 20
    var colorHigh = false
    var colorCharging = false
    var temperatureUnit = TemperatureUnit.both
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
                key: "no-battery", percent: nil, charging: false, texts: [],
                showGlyph: true, tint: nil)
        }
        let percent = snapshot.percent
        let charging = snapshot.isCharging
        let external = snapshot.externalConnected
        let texts = [config.primaryText, config.secondaryText]
            .compactMap { text(for: $0, snapshot: snapshot, unit: config.temperatureUnit) }
        let tint = tintColor(percent: percent, charging: charging, external: external, config: config)

        let key = "\(percent)|\(charging)|\(external)|\(config.showGlyph)|\(texts.joined(separator: "·"))|\(tint?.description ?? "template")"
        return cachedRender(
            key: key, percent: percent, charging: charging, texts: texts,
            showGlyph: config.showGlyph, tint: tint)
    }

    private static func cachedRender(
        key: String, percent: Int?, charging: Bool, texts: [String], showGlyph: Bool, tint: NSColor?
    ) -> NSImage {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image = render(
            percent: percent, charging: charging, texts: texts,
            showGlyph: showGlyph, tint: tint)
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Status ladder: charging blue, critical red, low orange, full green,
    /// monochrome template otherwise. Each rung is user-toggleable.
    private static func tintColor(
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
            return "H\(Int(snapshot.healthPercent.rounded()))%"
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
        percent: Int?, charging: Bool, texts: [String], showGlyph: Bool, tint: NSColor?
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
                        fillFraction: percent.map { CGFloat($0) / 100 }))
                x += glyphSize.width + 4
            }
            if !string.isEmpty {
                (string as NSString).draw(
                    at: NSPoint(x: x, y: (height - textSize.height) / 2 + 0.5),
                    withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = tint == nil
        return image
    }
}
