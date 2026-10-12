// Regenerate with: swift -module-cache-path build/ModuleCache scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/QuadRDP.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 1024)
    scale.concat()

    let base = rounded(NSRect(x: 64, y: 64, width: 896, height: 896), 202)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x07141D, 0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x172832).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x2B4149), ending: color(0x101D28))!.draw(in: base, angle: -65)
    color(0xA5EBD7, 0.13).setStroke()
    base.lineWidth = 3
    base.stroke()

    // Four independent desktops, with the upper-left desktop in focus.
    for row in 0..<2 {
        for column in 0..<2 {
            let active = row == 1 && column == 0
            let frame = NSRect(x: 182 + column * 350, y: 215 + row * 320, width: 310, height: 274)
            let panel = rounded(frame, 39)
            NSGraphicsContext.saveGraphicsState()
            let panelShadow = NSShadow()
            panelShadow.shadowColor = color(0x000B15, 0.35)
            panelShadow.shadowBlurRadius = 18
            panelShadow.shadowOffset = NSSize(width: 0, height: -10)
            panelShadow.set()
            color(active ? 0x8FF2D1 : 0x385D67).setFill()
            panel.fill()
            NSGraphicsContext.restoreGraphicsState()
            let top = color(active ? 0xA4F7D9 : 0x477680)
            let bottom = color(active ? 0x4BC6AA : 0x254752)
            NSGradient(starting: bottom, ending: top)!.draw(in: panel, angle: 90)
            color(active ? 0xC1FFE8 : 0x71B5B4, active ? 0.9 : 0.65).setStroke()
            panel.lineWidth = active ? 9 : 7
            panel.stroke()

            // The narrow toolbar makes these read as remote desktop windows.
            let toolbarY = frame.maxY - 56
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: frame.minX + 20, y: toolbarY))
            divider.line(to: NSPoint(x: frame.maxX - 20, y: toolbarY))
            divider.lineWidth = 5
            color(active ? 0x267D70 : 0x9BDAD0, 0.48).setStroke()
            divider.stroke()
            if size >= 64 {
                for dot in 0..<3 {
                    color(active ? 0x226C61 : 0xA5DCD3, 0.7).setFill()
                    NSBezierPath(ovalIn: NSRect(x: frame.minX + 25 + CGFloat(dot) * 21,
                                               y: frame.maxY - 33, width: 10, height: 10)).fill()
                }
            }
        }
    }

    // A cursor identifies interactive remote access and adds a clear focal point.
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 301, y: 729))
    cursor.line(to: NSPoint(x: 307, y: 601))
    cursor.line(to: NSPoint(x: 341, y: 631))
    cursor.line(to: NSPoint(x: 369, y: 581))
    cursor.line(to: NSPoint(x: 396, y: 596))
    cursor.line(to: NSPoint(x: 367, y: 645))
    cursor.line(to: NSPoint(x: 413, y: 654))
    cursor.close()
    color(0x173E40).setFill()
    cursor.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 1 ? "" : "@2x"
        let name = "icon_\(size)x\(size)\(suffix).png"
        try drawIcon(size: size * factor).write(to: iconset.appendingPathComponent(name))
    }
}

// Package the PNG representations directly, without invoking an image-conversion service.
func record(_ type: String, _ payload: Data) -> Data {
    var result = Data(type.utf8)
    var length = UInt32(payload.count + 8).bigEndian
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    result.append(payload)
    return result
}
let representations = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var entries = Data()
var tableOfContents = Data()
for (type, filename) in representations {
    let entry = record(type, try Data(contentsOf: iconset.appendingPathComponent(filename)))
    tableOfContents.append(entry.prefix(8))
    entries.append(entry)
}
try record("icns", record("TOC ", tableOfContents) + entries)
    .write(to: root.appendingPathComponent("Resources/QuadRDP.icns"), options: .atomic)
print("Generated Resources/QuadRDP.icns (16–1024 px)")
