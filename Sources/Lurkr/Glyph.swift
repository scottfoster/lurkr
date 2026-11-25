import AppKit

/// Lurkr's glyph: a half-lidded eye glancing sideways — someone quietly lurking.
/// Drawn in a 16×16 unit box with a y-down (flipped) coordinate system.
/// Also compiled into Tools/render_icons, so the app icon uses the same shape.
enum Glyph {
    static func draw(in rect: NSRect, color: NSColor) {
        let s = rect.width / 16.0
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        // Eye opening: a nearly flat upper lid over a deep lower curve.
        let eye = NSBezierPath()
        eye.move(to: p(1.0, 6.2))
        eye.curve(to: p(15.0, 6.2), controlPoint1: p(5.0, 3.4), controlPoint2: p(11.0, 3.4))
        eye.curve(to: p(1.0, 6.2), controlPoint1: p(13.4, 15.0), controlPoint2: p(2.6, 15.0))
        eye.close()

        color.setStroke()
        color.setFill()

        eye.lineWidth = 2.0 * s
        eye.lineJoinStyle = .round
        eye.stroke()

        // Pupil glancing to the left, clipped to the eye opening.
        NSGraphicsContext.saveGraphicsState()
        eye.addClip()
        let r: CGFloat = 3.1
        NSBezierPath(ovalIn: NSRect(x: rect.minX + (5.8 - r) * s,
                                    y: rect.minY + (9.4 - r) * s,
                                    width: 2 * r * s, height: 2 * r * s)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Heavy upper lid — the "lurking" half-closed look.
        let lid = NSBezierPath()
        lid.move(to: p(0.6, 5.4))
        lid.curve(to: p(15.4, 5.4), controlPoint1: p(5.0, 2.5), controlPoint2: p(11.0, 2.5))
        lid.lineWidth = 2.8 * s
        lid.lineCapStyle = .round
        lid.stroke()
    }
}
