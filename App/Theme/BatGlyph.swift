import AppKit

/// The bat-battery mark: a standard battery outline whose top edge grows two
/// small bat ears. Drawn in code so the menu bar, popover header and app
/// icon all share exact geometry.
enum BatGlyph {
    struct Style {
        var color: NSColor = .black
        var charging = false
        /// 0...1 fill level, nil hides the fill bar.
        var fillFraction: CGFloat?
    }

    /// Draws the glyph into `rect` (non-flipped coordinates).
    static func draw(in rect: NSRect, style: Style) {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        let stroke = max(h * 0.075, 1)
        let earHeight = h * 0.22

        let bodyWidth = w * 0.84
        let bodyHeight = h - earHeight - stroke
        let body = NSRect(
            x: x0 + stroke / 2, y: y0 + stroke / 2, width: bodyWidth, height: bodyHeight)
        let bodyRadius = bodyHeight * 0.26

        style.color.setStroke()
        style.color.setFill()

        let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius)
        bodyPath.lineWidth = stroke
        bodyPath.stroke()

        // Ears: two rounded triangles growing from the body's top edge.
        let earTop = y0 + h
        let bodyTop = body.maxY - stroke / 2
        for centerFraction in [0.26, 0.60] {
            let earCenter = x0 + bodyWidth * centerFraction
            let earHalf = bodyWidth * 0.085
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: earCenter - earHalf, y: bodyTop))
            ear.curve(
                to: NSPoint(x: earCenter, y: earTop),
                controlPoint1: NSPoint(x: earCenter - earHalf * 0.6, y: bodyTop + earHeight * 0.5),
                controlPoint2: NSPoint(x: earCenter - earHalf * 0.25, y: earTop - earHeight * 0.15))
            ear.curve(
                to: NSPoint(x: earCenter + earHalf, y: bodyTop),
                controlPoint1: NSPoint(x: earCenter + earHalf * 0.25, y: earTop - earHeight * 0.15),
                controlPoint2: NSPoint(x: earCenter + earHalf * 0.6, y: bodyTop + earHeight * 0.5))
            ear.close()
            ear.fill()
        }

        // Terminal nub.
        let nubHeight = bodyHeight * 0.42
        let nub = NSRect(
            x: body.maxX + stroke * 0.6,
            y: body.midY - nubHeight / 2,
            width: w * 0.09,
            height: nubHeight)
        NSBezierPath(roundedRect: nub, xRadius: nub.width * 0.45, yRadius: nub.width * 0.45).fill()

        // Fill level.
        if let fraction = style.fillFraction {
            let inset = stroke * 2.1
            let inner = body.insetBy(dx: inset, dy: inset)
            let filled = NSRect(
                x: inner.minX, y: inner.minY,
                width: inner.width * min(max(fraction, 0), 1), height: inner.height)
            if filled.width > 1 {
                NSBezierPath(
                    roundedRect: filled,
                    xRadius: inner.height * 0.18, yRadius: inner.height * 0.18
                ).fill()
            }
        }

        // Charging bolt, punched out of whatever is underneath so it stays
        // visible in template rendering.
        if style.charging {
            let bolt = NSBezierPath()
            let cx = body.midX
            let cy = body.midY
            let s = bodyHeight * 0.5
            bolt.move(to: NSPoint(x: cx + s * 0.16, y: cy + s * 0.95))
            bolt.line(to: NSPoint(x: cx - s * 0.42, y: cy - s * 0.12))
            bolt.line(to: NSPoint(x: cx - s * 0.04, y: cy - s * 0.12))
            bolt.line(to: NSPoint(x: cx - s * 0.16, y: cy - s * 0.95))
            bolt.line(to: NSPoint(x: cx + s * 0.42, y: cy + s * 0.12))
            bolt.line(to: NSPoint(x: cx + s * 0.04, y: cy + s * 0.12))
            bolt.close()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            bolt.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
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
