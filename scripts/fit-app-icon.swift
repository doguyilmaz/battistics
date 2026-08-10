#!/usr/bin/env swift
// Fits raw icon artwork to the macOS app icon template: finds the plate in
// the source (works for black or transparent surrounds), crops it, masks it
// with the standard squircle radius and centers it on a transparent canvas
// at the standard plate proportion.
// Usage: swift scripts/fit-app-icon.swift <in.png> <out.png> [canvasSize=1024]

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: fit-app-icon.swift <in.png> <out.png> [canvasSize]")
    exit(1)
}
let inputPath = arguments[1]
let outputPath = arguments[2]
let canvasSize = arguments.count > 3 ? Int(arguments[3]) ?? 1024 : 1024

guard let source = NSImage(contentsOfFile: inputPath),
    let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("error: cannot read \(inputPath)")
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
guard
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    print("error: cannot create context")
    exit(1)
}
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
    print("error: no pixel data")
    exit(1)
}

// The plate is anything visibly brighter than the (black or transparent)
// surround. Shadows stay below the threshold.
func isPlate(_ x: Int, _ y: Int) -> Bool {
    let offset = 4 * (y * width + x)
    let alpha = pixels[offset + 3]
    guard alpha > 16 else { return false }
    let luminance = max(pixels[offset], max(pixels[offset + 1], pixels[offset + 2]))
    return luminance > 14
}

var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where isPlate(x, y) {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX > minX, maxY > minY else {
    print("error: no plate found in \(inputPath)")
    exit(1)
}

// Keep the plate square by using the larger side, centered.
let side = max(maxX - minX + 1, maxY - minY + 1)
let centerX = (minX + maxX) / 2
let centerY = (minY + maxY) / 2
let cropRect = CGRect(
    x: max(centerX - side / 2, 0), y: max(centerY - side / 2, 0),
    width: min(side, width), height: min(side, height))
guard let plate = cgImage.cropping(to: cropRect) else {
    print("error: crop failed")
    exit(1)
}

// Standard macOS icon geometry: plate is 824/1024 of the canvas with a
// corner radius of about 185/824.
let plateSide = CGFloat(canvasSize) * 824.0 / 1024.0
let cornerRadius = plateSide * 185.0 / 824.0
let origin = (CGFloat(canvasSize) - plateSide) / 2
let plateRect = NSRect(x: origin, y: origin, width: plateSide, height: plateSide)

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: canvasSize, pixelsHigh: canvasSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
else {
    print("error: cannot create output rep")
    exit(1)
}
rep.size = NSSize(width: canvasSize, height: canvasSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSBezierPath(roundedRect: plateRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
NSGraphicsContext.current?.cgContext.draw(plate, in: plateRect)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("error: png encode failed")
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (canvas \(canvasSize), plate \(Int(plateSide)))")
