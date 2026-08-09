#!/usr/bin/env swift
// Generates the AppIcon PNG set from code. No source art needed: the icon
// is the same bat-battery mark the app draws at runtime.
// Usage: swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Resources/Assets.xcassets/AppIcon.appiconset"

func drawMaster(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let margin = size * 0.098
        let plate = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
        let radius = plate.width * 0.225

        let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.46, alpha: 1),
                NSColor(calibratedRed: 0.07, green: 0.065, blue: 0.19, alpha: 1),
            ])
        gradient?.draw(in: platePath, angle: -90)

        // Soft glow behind the glyph.
        let glow = NSGradient(
            starting: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.28),
            ending: NSColor.clear)
        glow?.draw(
            fromCenter: NSPoint(x: size / 2, y: size / 2), radius: 0,
            toCenter: NSPoint(x: size / 2, y: size / 2), radius: plate.width * 0.46,
            options: [])

        // Bat-battery glyph.
        let glyphWidth = plate.width * 0.62
        let glyphHeight = glyphWidth * 0.56
        let glyph = NSRect(
            x: plate.midX - glyphWidth / 2, y: plate.midY - glyphHeight / 2,
            width: glyphWidth, height: glyphHeight)

        let stroke = glyphHeight * 0.075
        let earHeight = glyphHeight * 0.22
        let bodyWidth = glyph.width * 0.84
        let bodyHeight = glyph.height - earHeight - stroke
        let body = NSRect(
            x: glyph.minX + stroke / 2, y: glyph.minY + stroke / 2,
            width: bodyWidth, height: bodyHeight)
        let bodyRadius = bodyHeight * 0.26

        let white = NSColor(calibratedWhite: 0.96, alpha: 1)
        white.setStroke()
        white.setFill()

        let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius)
        bodyPath.lineWidth = stroke
        bodyPath.stroke()

        let earTop = glyph.minY + glyph.height
        let bodyTop = body.maxY - stroke / 2
        for centerFraction in [0.26, 0.60] {
            let earCenter = glyph.minX + bodyWidth * centerFraction
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

        let nubHeight = bodyHeight * 0.42
        let nub = NSRect(
            x: body.maxX + stroke * 0.6, y: body.midY - nubHeight / 2,
            width: glyph.width * 0.09, height: nubHeight)
        NSBezierPath(roundedRect: nub, xRadius: nub.width * 0.45, yRadius: nub.width * 0.45).fill()

        // Green charge fill at 72%.
        let inset = stroke * 2.1
        let inner = body.insetBy(dx: inset, dy: inset)
        let filled = NSRect(x: inner.minX, y: inner.minY, width: inner.width * 0.72, height: inner.height)
        NSColor(calibratedRed: 0.24, green: 0.78, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: filled, xRadius: inner.height * 0.18, yRadius: inner.height * 0.18
        ).fill()

        return true
    }
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw NSError(domain: "icon", code: 1) }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try data.write(to: url)
}

let master = drawMaster(size: 1024)
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let files: [(String, Int)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]
for (name, pixels) in files {
    try writePNG(master, pixels: pixels, to: outputURL.appendingPathComponent(name))
    print("wrote \(name) (\(pixels)px)")
}
