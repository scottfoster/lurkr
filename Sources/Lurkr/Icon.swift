import AppKit

enum Icon {
    static let grey: NSImage = base(color: .black, isTemplate: true)
    static let purple: NSImage = base(color: brandPurple, isTemplate: false)

    private static let brandPurple = NSColor(red: 0.576, green: 0.247, blue: 1.0, alpha: 1.0)
    private static let canvasSize: CGFloat = 18

    /// Purple Lurkr eye with a small red count badge in the top-right.
    /// For counts ≥ 10 the badge reads "9+".
    static func purpleWithBadge(count: Int) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let img = NSImage(size: size)
        img.lockFocus()
        purple.draw(at: .zero,
                    from: NSRect(origin: .zero, size: size),
                    operation: .sourceOver,
                    fraction: 1.0)
        drawBadge(count: count)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private static func base(color: NSColor, isTemplate: Bool) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let img = NSImage(size: size, flipped: true) { _ in
            drawGlyph(color: color)
            return true
        }
        img.isTemplate = isTemplate
        return img
    }

    private static func drawGlyph(color: NSColor) {
        Glyph.draw(in: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize), color: color)
    }

    /// Drawn in standard bottom-left AppKit coords (the wrapping context here is NOT flipped).
    /// Top-right corner of the 18×18 canvas.
    private static func drawBadge(count: Int) {
        let diameter: CGFloat = 11
        let rect = NSRect(
            x: canvasSize - diameter,
            y: canvasSize - diameter,
            width: diameter,
            height: diameter
        )

        // Thin white ring for separation from the purple glyph beneath.
        let ringRect = rect.insetBy(dx: -1, dy: -1)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: ringRect,
                     xRadius: ringRect.width / 2,
                     yRadius: ringRect.width / 2).fill()

        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: diameter / 2,
                     yRadius: diameter / 2).fill()

        let text = count > 9 ? "9+" : "\(count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let pt = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        str.draw(at: pt)
    }
}
