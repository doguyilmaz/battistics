#!/usr/bin/env swift
// Renders the AppIcon PNG set from a square source artwork.
// Usage: swift scripts/make-icon-from-art.swift art/icon-art.png App/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit

guard CommandLine.arguments.count > 2 else {
    print("usage: make-icon-from-art.swift <source.png> <output-appiconset-dir>")
    exit(1)
}
let sourcePath = CommandLine.arguments[1]
let outputDirectory = CommandLine.arguments[2]

guard let source = NSImage(contentsOfFile: sourcePath) else {
    print("error: cannot read \(sourcePath)")
    exit(1)
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
    try writePNG(source, pixels: pixels, to: outputURL.appendingPathComponent(name))
    print("wrote \(name) (\(pixels)px)")
}
