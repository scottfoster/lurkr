import AppKit

enum Icon {
    static let grey: NSImage = base(color: .black, isTemplate: true)
    static let purple: NSImage = base(color: brandPurple, isTemplate: false)

    private static let brandPurple = NSColor(red: 0.576, green: 0.247, blue: 1.0, alpha: 1.0)
    private static let canvasSize: CGFloat = 18

    /// Purple Twitch glitch with a small red count badge in the top-right.
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
            drawGlitch(color: color)
            return true
        }
        img.isTemplate = isTemplate
        return img
    }

    private static func drawGlitch(color: NSColor) {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        let s: CGFloat = canvasSize / 16.0
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

        // Outer outline
        path.move(to: p(3.857, 0));   path.line(to: p(1, 2.857))
        path.line(to: p(1, 13.143));  path.line(to: p(4.429, 13.143))
        path.line(to: p(4.429, 16));  path.line(to: p(7.286, 13.143))
        path.line(to: p(9.571, 13.143)); path.line(to: p(14.714, 8))
        path.line(to: p(14.714, 0));  path.close()

        // Inner hole
        path.move(to: p(13.571, 7.429))
        path.line(to: p(11.286, 9.714)); path.line(to: p(9, 9.714))
        path.line(to: p(7, 11.714));     path.line(to: p(7, 9.714))
        path.line(to: p(4.429, 9.714));  path.line(to: p(4.429, 1.143))
        path.line(to: p(13.571, 1.143)); path.close()

        // Right eye
        path.move(to: p(10.714, 3.143)); path.line(to: p(11.857, 3.143))
        path.line(to: p(11.857, 6.571)); path.line(to: p(10.714, 6.571))
        path.close()

        // Left eye
        path.move(to: p(7.571, 3.143));  path.line(to: p(8.714, 3.143))
        path.line(to: p(8.714, 6.571));  path.line(to: p(7.571, 6.571))
        path.close()

        color.setFill()
        path.fill()
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
