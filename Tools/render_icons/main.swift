import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render_icons <output_iconset_dir>\n".data(using: .utf8)!)
    exit(1)
}

let outDir = CommandLine.arguments[1]

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        // Purple rounded background
        let corner = size * 0.22
        let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                              xRadius: corner, yRadius: corner)
        NSColor(red: 0.576, green: 0.247, blue: 1.0, alpha: 1.0).setFill()
        bg.fill()

        // White Lurkr eye glyph (Sources/Lurkr/Glyph.swift), padded inset
        let pad = size * 0.18
        Glyph.draw(in: NSRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad),
                   color: .white)
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
