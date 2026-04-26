#!/usr/bin/env swift
//
// generate-app-icon.swift
//
// TypeToTalk app icon generator.
// Renders a 1024x1024 PNG with an orange squircle background and three white "T"
// glyphs arranged diagonally (lower-left -> center -> upper-right) with depth via
// alpha falloff (back T = 0.7, middle = 0.85, front = 1.0). Each T is rotated -15°.
//
// Usage:
//   swift tools/generate-app-icon.swift
//
// Output:
//   tools/AppIcon-1024.png
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Configuration

let canvasSize: CGFloat = 1024
let cornerRadius: CGFloat = 220   // squircle approximation
let backgroundHex = "#DE822F"     // Color.appOrange (TimeCamera- 統一)

let fontName = "Helvetica-Bold"
let fontSize: CGFloat = 540
let glyph = "T"
let rotationDegrees: CGFloat = -15

// Offsets of each T from canvas center (x, y) in points.
// y is in CoreGraphics coordinates (up is positive).
struct TPlacement {
    let offset: CGPoint
    let alpha: CGFloat
}

let placements: [TPlacement] = [
    TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),  // back (lower-left visually -> drawn first)
    TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),  // middle
    TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),  // front (upper-right visually -> drawn last)
]

// Note about coordinates:
// In CoreGraphics, +y is upward. Visually we want the back T to appear at the
// LOWER-LEFT of the canvas and the front T at the UPPER-RIGHT. With +y up,
// "lower" means y < center and "upper" means y > center. We flip the y axis
// while drawing the glyph (see drawT) so positive y in the offset maps to the
// LOWER side of the rendered icon, matching the spec text in the task brief
// (-180, +180) / (0,0) / (+180, -180).
//
// To keep the math obvious, we treat the offset above as (x_right, y_down):
//   - x positive => moves right
//   - y positive => moves down (i.e. visually lower)
// We translate by (centerX + offset.x, centerY - offset.y) when drawing.

// MARK: - Helpers

func parseHex(_ hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else {
        fatalError("Invalid hex color: \(hex)")
    }
    let r = CGFloat((v >> 16) & 0xFF) / 255.0
    let g = CGFloat((v >>  8) & 0xFF) / 255.0
    let b = CGFloat( v        & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
}

func makeContext(size: CGFloat) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Failed to create CGContext")
    }
    return ctx
}

func drawSquircleBackground(in ctx: CGContext, size: CGFloat, radius: CGFloat, color: CGColor) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

/// Draws a single white "T" centered at (centerX + offset.x, centerY - offset.y),
/// rotated by rotationDegrees, with the given alpha.
func drawT(in ctx: CGContext, canvas: CGFloat, offset: CGPoint, alpha: CGFloat) {
    let center = CGPoint(x: canvas / 2 + offset.x, y: canvas / 2 - offset.y)

    // Build attributed string for the glyph.
    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
    ]
    let attributed = NSAttributedString(string: glyph, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)

    // Measure glyph bounds (typographic) so we can center it precisely.
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])

    ctx.saveGState()

    // Move origin to the desired draw center, rotate, then back-shift by half-bounds
    // so the glyph's own visual center sits on the rotation pivot.
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotationDegrees * .pi / 180)
    let drawOriginX = -bounds.midX
    let drawOriginY = -bounds.midY
    ctx.textPosition = CGPoint(x: drawOriginX, y: drawOriginY)
    CTLineDraw(line, ctx)

    ctx.restoreGState()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate-app-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url, options: .atomic)
}

// MARK: - Main

let ctx = makeContext(size: canvasSize)

// Ensure background starts fully transparent (squircle will fill the visible area).
ctx.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

// 1. Squircle orange background.
drawSquircleBackground(in: ctx, size: canvasSize, radius: cornerRadius, color: parseHex(backgroundHex))

// 2. Three Ts, back-to-front.
for placement in placements {
    drawT(in: ctx, canvas: canvasSize, offset: placement.offset, alpha: placement.alpha)
}

guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("Failed to materialize CGImage\n".utf8))
    exit(1)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let toolsDir = scriptURL.deletingLastPathComponent()
let outputURL = toolsDir.appendingPathComponent("AppIcon-1024.png")

do {
    try FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)
    try writePNG(cgImage, to: outputURL)
    print("Wrote \(outputURL.path) (\(cgImage.width)x\(cgImage.height))")
} catch {
    FileHandle.standardError.write(Data("Failed to write PNG: \(error)\n".utf8))
    exit(1)
}
