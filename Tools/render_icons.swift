#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render_icons.swift <output_iconset_dir>\n".data(using: .utf8)!)
    exit(1)
}

let outDir = CommandLine.arguments[1]

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        // Purple rounded background (Twitch brand)
        let corner = size * 0.22
        let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                              xRadius: corner, yRadius: corner)
        NSColor(red: 0.576, green: 0.247, blue: 1.0, alpha: 1.0).setFill()
        bg.fill()

        // White Twitch glitch glyph (16x16 path coords, padded inset)
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        let pad = size * 0.20
        let glyph = size - 2 * pad
        let scale = glyph / 16.0
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: pad + x * scale, y: pad + y * scale)
        }

        path.move(to: p(3.857, 0));   path.line(to: p(1, 2.857))
        path.line(to: p(1, 13.143));  path.line(to: p(4.429, 13.143))
        path.line(to: p(4.429, 16));  path.line(to: p(7.286, 13.143))
        path.line(to: p(9.571, 13.143)); path.line(to: p(14.714, 8))
        path.line(to: p(14.714, 0));  path.close()

        path.move(to: p(13.571, 7.429))
        path.line(to: p(11.286, 9.714)); path.line(to: p(9, 9.714))
        path.line(to: p(7, 11.714));     path.line(to: p(7, 9.714))
        path.line(to: p(4.429, 9.714));  path.line(to: p(4.429, 1.143))
        path.line(to: p(13.571, 1.143)); path.close()

        path.move(to: p(10.714, 3.143)); path.line(to: p(11.857, 3.143))
        path.line(to: p(11.857, 6.571)); path.line(to: p(10.714, 6.571))
        path.close()

        path.move(to: p(7.571, 3.143));  path.line(to: p(8.714, 3.143))
        path.line(to: p(8.714, 6.571));  path.line(to: p(7.571, 6.571))
        path.close()

        NSColor.white.setFill()
        path.fill()
        return true
    }
    return img
}

func writePNG(_ img: NSImage, to path: String) throws {
    let size = img.size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let img = drawIcon(size: px)
    try writePNG(img, to: "\(outDir)/\(name)")
}
print("rendered \(sizes.count) icons → \(outDir)")
