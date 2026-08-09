import AppKit

/// The bat-battery mark, matching the app icon silhouette: a battery body
/// with two ears on top and a wing-scalloped bottom edge meeting in a
/// center point. Interior shows a lightning bolt while charging, otherwise
/// a fill bar at the current charge level.
enum BatGlyph {
    struct Style {
        var color: NSColor = .black
        var charging = false
        /// 0...1 fill level, nil hides the fill bar.
        var fillFraction: CGFloat?
    }

    /// Draws the glyph into `rect` (non-flipped coordinates).
    static func draw(in rect: NSRect, style: Style) {
        let stroke = max(rect.height * 0.075, 1.2)
        let earHeight = rect.height * 0.20
        let wingHeight = rect.height * 0.16
        let bodyWidth = rect.width * 0.87
        let left = rect.minX + stroke / 2
        let right = left + bodyWidth
        let top = rect.maxY - earHeight - stroke / 2
        let bottom = rect.minY + wingHeight + stroke / 2
        let radius = (top - bottom) * 0.24
        let midX = (left + right) / 2

        style.color.setStroke()
        style.color.setFill()

        let outline = NSBezierPath()
        outline.lineWidth = stroke
        outline.lineJoinStyle = .round
        outline.lineCapStyle = .round

        // Left edge, bottom to top.
        outline.move(to: NSPoint(x: left, y: bottom + radius))
        outline.line(to: NSPoint(x: left, y: top - radius))
        outline.curve(
            to: NSPoint(x: left + radius, y: top),
            controlPoint1: NSPoint(x: left, y: top - radius * 0.45),
            controlPoint2: NSPoint(x: left + radius * 0.45, y: top))

        // Two ears along the top edge.
        for earCenter in [left + bodyWidth * 0.30, left + bodyWidth * 0.62] {
            let half = bodyWidth * 0.095
            let peak = rect.maxY
            outline.line(to: NSPoint(x: earCenter - half, y: top))
            outline.curve(
                to: NSPoint(x: earCenter - half * 0.1, y: peak),
                controlPoint1: NSPoint(x: earCenter - half * 0.6, y: top + earHeight * 0.5),
                controlPoint2: NSPoint(x: earCenter - half * 0.25, y: peak - earHeight * 0.1))
            outline.curve(
                to: NSPoint(x: earCenter + half, y: top),
                controlPoint1: NSPoint(x: earCenter + half * 0.15, y: peak - earHeight * 0.3),
                controlPoint2: NSPoint(x: earCenter + half * 0.6, y: top + earHeight * 0.4))
        }

        // Top-right corner and right edge.
        outline.line(to: NSPoint(x: right - radius, y: top))
        outline.curve(
            to: NSPoint(x: right, y: top - radius),
            controlPoint1: NSPoint(x: right - radius * 0.45, y: top),
            controlPoint2: NSPoint(x: right, y: top - radius * 0.45))
        outline.line(to: NSPoint(x: right, y: bottom + radius))
        outline.curve(
            to: NSPoint(x: right - radius, y: bottom),
            controlPoint1: NSPoint(x: right, y: bottom + radius * 0.45),
            controlPoint2: NSPoint(x: right - radius * 0.45, y: bottom))

        // Wing-scalloped bottom: two concave arcs meeting in a point.
        outline.curve(
            to: NSPoint(x: midX, y: rect.minY),
            controlPoint1: NSPoint(x: left + bodyWidth * 0.68, y: bottom - wingHeight * 0.1),
            controlPoint2: NSPoint(x: left + bodyWidth * 0.58, y: rect.minY + wingHeight * 0.25))
        outline.curve(
            to: NSPoint(x: left + radius, y: bottom),
            controlPoint1: NSPoint(x: left + bodyWidth * 0.42, y: rect.minY + wingHeight * 0.25),
            controlPoint2: NSPoint(x: left + bodyWidth * 0.32, y: bottom - wingHeight * 0.1))
        outline.curve(
            to: NSPoint(x: left, y: bottom + radius),
            controlPoint1: NSPoint(x: left + radius * 0.45, y: bottom),
            controlPoint2: NSPoint(x: left, y: bottom + radius * 0.45))
        outline.close()
        outline.stroke()

        // Terminal nub on the right.
        let nubHeight = (top - bottom) * 0.40
        let nub = NSRect(
            x: right + stroke * 0.7,
            y: (top + bottom) / 2 - nubHeight / 2,
            width: rect.width * 0.075,
            height: nubHeight)
        NSBezierPath(roundedRect: nub, xRadius: nub.width * 0.45, yRadius: nub.width * 0.45).fill()

        // Interior: bolt while charging, fill level otherwise.
        if style.charging {
            let bolt = NSBezierPath()
            let cx = midX
            let cy = (top + bottom) / 2
            let s = (top - bottom) * 0.60
            bolt.move(to: NSPoint(x: cx + s * 0.18, y: cy + s * 0.95))
            bolt.line(to: NSPoint(x: cx - s * 0.45, y: cy - s * 0.10))
            bolt.line(to: NSPoint(x: cx - s * 0.05, y: cy - s * 0.10))
            bolt.line(to: NSPoint(x: cx - s * 0.18, y: cy - s * 0.95))
            bolt.line(to: NSPoint(x: cx + s * 0.45, y: cy + s * 0.10))
            bolt.line(to: NSPoint(x: cx + s * 0.05, y: cy + s * 0.10))
            bolt.close()
            bolt.fill()
        } else if let fraction = style.fillFraction {
            let inset = stroke * 1.9
            let inner = NSRect(
                x: left + inset, y: bottom + inset * 0.8,
                width: bodyWidth - inset * 2, height: (top - bottom) - inset * 1.6)
            let filled = NSRect(
                x: inner.minX, y: inner.minY,
                width: inner.width * min(max(fraction, 0), 1), height: inner.height)
            if filled.width > 1 {
                style.color.withAlphaComponent(0.55).setFill()
                NSBezierPath(
                    roundedRect: filled,
                    xRadius: inner.height * 0.22, yRadius: inner.height * 0.22
                ).fill()
                style.color.setFill()
            }
        }
    }

    /// Standalone glyph image, template unless a color is given.
    static func image(size: NSSize, fillFraction: CGFloat?, charging: Bool, color: NSColor? = nil) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(
                in: rect,
                style: Style(
                    color: color ?? .black, charging: charging, fillFraction: fillFraction))
            return true
        }
        image.isTemplate = color == nil
        return image
    }
}
