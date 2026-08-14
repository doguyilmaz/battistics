import AppKit

/// Menu bar glyph renderer. Five styles, all drawn in code so every one
/// supports live fill level, a charging bolt, template rendering and status
/// tinting at any size:
///   bat      battery silhouette with ears and wing-scalloped bottom
///   classic  plain battery
///   gauge    speedometer arc, the needle angle is the charge level
///   stats    battery with chart bars that light up with the charge level
///   wings    bat silhouette that fills up with charge
enum BatGlyph {
    struct Style {
        var color: NSColor = .black
        var charging = false
        /// 0...1 fill level, nil hides the level indication.
        var fillFraction: CGFloat?
        var shape: MenuBarIconStyle = .bat
    }

    /// Draws the glyph into `rect` (non-flipped coordinates).
    static func draw(in rect: NSRect, style: Style) {
        style.color.setStroke()
        style.color.setFill()
        switch style.shape {
        case .bat, .classic:
            drawBattery(in: rect, style: style)
        case .gauge:
            drawGauge(in: rect, style: style)
        case .stats:
            drawStats(in: rect, style: style)
        case .wings:
            drawWings(in: rect, style: style)
        }
    }

    /// Standalone glyph image, template unless a color is given.
    static func image(
        size: NSSize, fillFraction: CGFloat?, charging: Bool, color: NSColor? = nil,
        shape: MenuBarIconStyle = .bat
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(
                in: rect,
                style: Style(
                    color: color ?? .black, charging: charging, fillFraction: fillFraction,
                    shape: shape))
            return true
        }
        image.isTemplate = color == nil
        return image
    }

    // MARK: - Battery bodies (bat and classic)

    private static func drawBattery(in rect: NSRect, style: Style) {
        let metrics = BodyMetrics(rect: rect, batShaped: style.shape == .bat)

        let outline = NSBezierPath()
        outline.lineWidth = metrics.stroke
        outline.lineJoinStyle = .round
        outline.lineCapStyle = .round

        if style.shape == .classic {
            outline.appendRoundedRect(
                NSRect(
                    x: metrics.left, y: metrics.bottom,
                    width: metrics.bodyWidth, height: metrics.top - metrics.bottom),
                xRadius: metrics.radius, yRadius: metrics.radius)
        } else {
            appendBatBatteryOutline(to: outline, rect: rect, metrics: metrics)
        }
        outline.stroke()

        drawNub(in: rect, metrics: metrics)
        drawBatteryInterior(in: rect, style: style, metrics: metrics)
    }

    private struct BodyMetrics {
        let stroke: CGFloat
        let earHeight: CGFloat
        let wingHeight: CGFloat
        let bodyWidth: CGFloat
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        let radius: CGFloat
        let midX: CGFloat

        init(rect: NSRect, batShaped: Bool) {
            stroke = max(rect.height * 0.075, 1.2)
            earHeight = batShaped ? rect.height * 0.20 : 0
            wingHeight = batShaped ? rect.height * 0.16 : 0
            bodyWidth = rect.width * 0.87
            left = rect.minX + stroke / 2
            right = left + bodyWidth
            top = rect.maxY - earHeight - stroke / 2
            bottom = rect.minY + wingHeight + stroke / 2
            radius = (top - bottom) * 0.24
            midX = (left + right) / 2
        }
    }

    private static func appendBatBatteryOutline(
        to outline: NSBezierPath, rect: NSRect, metrics m: BodyMetrics
    ) {
        // Left edge, bottom to top.
        outline.move(to: NSPoint(x: m.left, y: m.bottom + m.radius))
        outline.line(to: NSPoint(x: m.left, y: m.top - m.radius))
        outline.curve(
            to: NSPoint(x: m.left + m.radius, y: m.top),
            controlPoint1: NSPoint(x: m.left, y: m.top - m.radius * 0.45),
            controlPoint2: NSPoint(x: m.left + m.radius * 0.45, y: m.top))

        // Two ears along the top edge.
        for earCenter in [m.left + m.bodyWidth * 0.30, m.left + m.bodyWidth * 0.62] {
            let half = m.bodyWidth * 0.095
            let peak = rect.maxY
            outline.line(to: NSPoint(x: earCenter - half, y: m.top))
            outline.curve(
                to: NSPoint(x: earCenter - half * 0.1, y: peak),
                controlPoint1: NSPoint(x: earCenter - half * 0.6, y: m.top + m.earHeight * 0.5),
                controlPoint2: NSPoint(x: earCenter - half * 0.25, y: peak - m.earHeight * 0.1))
            outline.curve(
                to: NSPoint(x: earCenter + half, y: m.top),
                controlPoint1: NSPoint(x: earCenter + half * 0.15, y: peak - m.earHeight * 0.3),
                controlPoint2: NSPoint(x: earCenter + half * 0.6, y: m.top + m.earHeight * 0.4))
        }

        // Top-right corner and right edge.
        outline.line(to: NSPoint(x: m.right - m.radius, y: m.top))
        outline.curve(
            to: NSPoint(x: m.right, y: m.top - m.radius),
            controlPoint1: NSPoint(x: m.right - m.radius * 0.45, y: m.top),
            controlPoint2: NSPoint(x: m.right, y: m.top - m.radius * 0.45))
        outline.line(to: NSPoint(x: m.right, y: m.bottom + m.radius))
        outline.curve(
            to: NSPoint(x: m.right - m.radius, y: m.bottom),
            controlPoint1: NSPoint(x: m.right, y: m.bottom + m.radius * 0.45),
            controlPoint2: NSPoint(x: m.right - m.radius * 0.45, y: m.bottom))

        // Wing-scalloped bottom: two concave arcs meeting in a point.
        outline.curve(
            to: NSPoint(x: m.midX, y: rect.minY),
            controlPoint1: NSPoint(x: m.left + m.bodyWidth * 0.68, y: m.bottom - m.wingHeight * 0.1),
            controlPoint2: NSPoint(x: m.left + m.bodyWidth * 0.58, y: rect.minY + m.wingHeight * 0.25))
        outline.curve(
            to: NSPoint(x: m.left + m.radius, y: m.bottom),
            controlPoint1: NSPoint(x: m.left + m.bodyWidth * 0.42, y: rect.minY + m.wingHeight * 0.25),
            controlPoint2: NSPoint(x: m.left + m.bodyWidth * 0.32, y: m.bottom - m.wingHeight * 0.1))
        outline.curve(
            to: NSPoint(x: m.left, y: m.bottom + m.radius),
            controlPoint1: NSPoint(x: m.left + m.radius * 0.45, y: m.bottom),
            controlPoint2: NSPoint(x: m.left, y: m.bottom + m.radius * 0.45))
        outline.close()
    }

    private static func drawNub(in rect: NSRect, metrics m: BodyMetrics) {
        let nubHeight = (m.top - m.bottom) * 0.40
        let nub = NSRect(
            x: m.right + m.stroke * 0.7,
            y: (m.top + m.bottom) / 2 - nubHeight / 2,
            width: rect.width * 0.075,
            height: nubHeight)
        NSBezierPath(roundedRect: nub, xRadius: nub.width * 0.45, yRadius: nub.width * 0.45).fill()
    }

    private static func drawBatteryInterior(in rect: NSRect, style: Style, metrics m: BodyMetrics) {
        if style.charging {
            boltPath(
                centerX: m.midX, centerY: (m.top + m.bottom) / 2,
                size: (m.top - m.bottom) * 0.60
            ).fill()
        } else if let fraction = style.fillFraction {
            let inset = m.stroke * 1.9
            let inner = NSRect(
                x: m.left + inset, y: m.bottom + inset * 0.8,
                width: m.bodyWidth - inset * 2, height: (m.top - m.bottom) - inset * 1.6)
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

    // MARK: - Gauge

    private static func drawGauge(in rect: NSRect, style: Style) {
        let stroke = max(rect.height * 0.09, 1.3)
        let cx = rect.midX
        let cy = rect.minY + rect.height * 0.16
        let radius = min(rect.width / 2, rect.height * 0.80) - stroke

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: cx, y: cy), radius: radius,
            startAngle: 180, endAngle: 0, clockwise: true)
        arc.lineWidth = stroke
        arc.lineCapStyle = .round
        arc.stroke()

        if style.charging {
            boltPath(centerX: cx, centerY: cy + radius * 0.42, size: radius * 0.75).fill()
            return
        }

        let fraction = min(max(style.fillFraction ?? 0, 0), 1)
        let angle = (180 - 180 * fraction) * CGFloat.pi / 180
        let needleLength = radius - stroke * 1.6
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx, y: cy))
        needle.line(
            to: NSPoint(x: cx + cos(angle) * needleLength, y: cy + sin(angle) * needleLength))
        needle.lineWidth = stroke
        needle.lineCapStyle = .round
        needle.stroke()

        let hubRadius = stroke * 0.9
        NSBezierPath(
            ovalIn: NSRect(x: cx - hubRadius, y: cy - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
        ).fill()
    }

    // MARK: - Stats (battery with chart bars)

    private static func drawStats(in rect: NSRect, style: Style) {
        let metrics = BodyMetrics(rect: rect, batShaped: false)

        let outline = NSBezierPath(
            roundedRect: NSRect(
                x: metrics.left, y: metrics.bottom,
                width: metrics.bodyWidth, height: metrics.top - metrics.bottom),
            xRadius: metrics.radius, yRadius: metrics.radius)
        outline.lineWidth = metrics.stroke
        outline.stroke()
        drawNub(in: rect, metrics: metrics)

        if style.charging {
            boltPath(
                centerX: metrics.midX, centerY: (metrics.top + metrics.bottom) / 2,
                size: (metrics.top - metrics.bottom) * 0.60
            ).fill()
            return
        }

        let inset = metrics.stroke * 2.0
        let inner = NSRect(
            x: metrics.left + inset, y: metrics.bottom + inset * 0.9,
            width: metrics.bodyWidth - inset * 2, height: (metrics.top - metrics.bottom) - inset * 1.8)
        let barCount = 5
        let gap = inner.width * 0.06
        let barWidth = (inner.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let heights: [CGFloat] = [0.34, 0.50, 0.68, 0.84, 1.0]
        let fraction = min(max(style.fillFraction ?? 0, 0), 1)
        let litBars = fraction <= 0 ? 0 : max(Int((fraction * CGFloat(barCount)).rounded(.up)), 1)

        for index in 0..<barCount {
            let bar = NSRect(
                x: inner.minX + CGFloat(index) * (barWidth + gap),
                y: inner.minY,
                width: barWidth,
                height: inner.height * heights[index])
            style.color.withAlphaComponent(index < litBars ? 1.0 : 0.25).setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth * 0.3, yRadius: barWidth * 0.3).fill()
        }
        style.color.setFill()
    }

    // MARK: - Wings (bat silhouette that fills with charge)

    private static func drawWings(in rect: NSRect, style: Style) {
        let path = batSilhouette(in: rect)
        let fraction = min(max(style.fillFraction ?? 0, 0), 1)

        if fraction > 0 || style.charging {
            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            let fillHeight = style.charging ? rect.height : rect.height * fraction
            style.color.withAlphaComponent(style.charging ? 0.9 : 0.6).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillHeight).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            style.color.setFill()
        }

        path.lineWidth = max(rect.height * 0.06, 1.0)
        path.lineJoinStyle = .round
        path.stroke()

        if style.charging {
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            boltPath(centerX: rect.midX, centerY: rect.midY * 1.05, size: rect.height * 0.42).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
    }

    private static func batSilhouette(in rect: NSRect) -> NSBezierPath {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func point(_ px: CGFloat, _ py: CGFloat) -> NSPoint {
            NSPoint(x: x0 + w * px, y: y0 + h * py)
        }

        let path = NSBezierPath()
        // Left wing tip, sweeping up to the head.
        path.move(to: point(0.03, 0.60))
        path.curve(to: point(0.40, 0.80), controlPoint1: point(0.13, 0.86), controlPoint2: point(0.28, 0.84))
        // Left ear.
        path.curve(to: point(0.43, 0.97), controlPoint1: point(0.41, 0.86), controlPoint2: point(0.41, 0.93))
        path.curve(to: point(0.50, 0.84), controlPoint1: point(0.46, 0.92), controlPoint2: point(0.48, 0.86))
        // Head dip and right ear.
        path.curve(to: point(0.57, 0.97), controlPoint1: point(0.52, 0.86), controlPoint2: point(0.54, 0.92))
        path.curve(to: point(0.60, 0.80), controlPoint1: point(0.59, 0.93), controlPoint2: point(0.59, 0.86))
        // Right wing to the tip.
        path.curve(to: point(0.97, 0.60), controlPoint1: point(0.72, 0.84), controlPoint2: point(0.87, 0.86))
        // Right wing underside scallops back to the body.
        path.curve(to: point(0.70, 0.36), controlPoint1: point(0.88, 0.44), controlPoint2: point(0.80, 0.36))
        path.curve(to: point(0.56, 0.24), controlPoint1: point(0.64, 0.36), controlPoint2: point(0.60, 0.30))
        // Body tail point.
        path.curve(to: point(0.50, 0.06), controlPoint1: point(0.53, 0.18), controlPoint2: point(0.51, 0.10))
        path.curve(to: point(0.44, 0.24), controlPoint1: point(0.49, 0.10), controlPoint2: point(0.47, 0.18))
        // Left wing underside scallops.
        path.curve(to: point(0.30, 0.36), controlPoint1: point(0.40, 0.30), controlPoint2: point(0.36, 0.36))
        path.curve(to: point(0.03, 0.60), controlPoint1: point(0.20, 0.36), controlPoint2: point(0.12, 0.44))
        path.close()
        return path
    }

    // MARK: - Shared bolt

    private static func boltPath(centerX cx: CGFloat, centerY cy: CGFloat, size s: CGFloat) -> NSBezierPath {
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: cx + s * 0.18, y: cy + s * 0.95))
        bolt.line(to: NSPoint(x: cx - s * 0.45, y: cy - s * 0.10))
        bolt.line(to: NSPoint(x: cx - s * 0.05, y: cy - s * 0.10))
        bolt.line(to: NSPoint(x: cx - s * 0.18, y: cy - s * 0.95))
        bolt.line(to: NSPoint(x: cx + s * 0.45, y: cy + s * 0.10))
        bolt.line(to: NSPoint(x: cx + s * 0.05, y: cy + s * 0.10))
        bolt.close()
        return bolt
    }
}
