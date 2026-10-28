// Renders the PaneFlow app icon: two window panes split by a draggable divider knob.
// Usage: swift scripts/make-icon.swift <output-dir>   (writes icon_1024.png)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Continuous-corner squircle (superellipse, n = 5) like the macOS icon shape.
func squircle(_ rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath()
    let n: CGFloat = 5, steps = 720
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * a * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * b * (s < 0 ? -1 : 1)
        let p = CGPoint(x: rect.midX + x, y: rect.midY + y)
        i == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    return path
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Drop shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x3B5BDB).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background gradient + soft highlight.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x6FA8FF), color(0x4C6EF5), color(0x6741D9)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: body, angle: -60)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: 330, y: 820), radius: 0, toCenter: CGPoint(x: 330, y: 820), radius: 560, options: [])

    // Window panes.
    func pane(_ rect: CGRect, alpha: CGFloat, tint: NSColor) {
        let radius: CGFloat = 40
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.35, alpha: 0.35)
        s.shadowBlurRadius = 24
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.set()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        // Title bar.
        let bar = CGRect(x: rect.minX, y: rect.maxY - 78, width: rect.width, height: 78)
        tint.setFill()
        bar.fill()
        for (i, hex) in [UInt32(0xFF6B6B), 0xFCC419, 0x51CF66].enumerated() {
            color(hex).setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.minX + 30 + CGFloat(i) * 36, y: bar.midY - 11, width: 22, height: 22)).fill()
        }
        // Content lines.
        let lineColor = color(0x4C6EF5, 0.16)
        lineColor.setFill()
        var y = bar.minY - 58
        for (i, fraction) in [0.78, 0.62, 0.7, 0.5, 0.66].enumerated() where y > rect.minY + 30 {
            let w = (rect.width - 60) * fraction
            NSBezierPath(roundedRect: CGRect(x: rect.minX + 30, y: y, width: w, height: i == 0 ? 30 : 20),
                         xRadius: 10, yRadius: 10).fill()
            y -= i == 0 ? 62 : 48
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    pane(CGRect(x: 176, y: 236, width: 318, height: 552), alpha: 0.96, tint: color(0xDBE4FF))
    pane(CGRect(x: 530, y: 236, width: 318, height: 552), alpha: 0.86, tint: color(0xE5DBFF))

    // Divider knob with ‹ › arrows.
    let center = CGPoint(x: 512, y: 512)
    NSGraphicsContext.saveGraphicsState()
    let ks = NSShadow()
    ks.shadowColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.4, alpha: 0.45)
    ks.shadowBlurRadius = 22
    ks.shadowOffset = NSSize(width: 0, height: -6)
    ks.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: CGRect(x: center.x - 9, y: 286, width: 18, height: 452), xRadius: 9, yRadius: 9).fill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let arrow = NSBezierPath()
    arrow.lineWidth = 13
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    // Double-headed horizontal arrow (resize), not angle brackets.
    arrow.move(to: CGPoint(x: center.x - 36, y: center.y))
    arrow.line(to: CGPoint(x: center.x + 36, y: center.y))
    arrow.move(to: CGPoint(x: center.x - 16, y: center.y + 20))
    arrow.line(to: CGPoint(x: center.x - 36, y: center.y))
    arrow.line(to: CGPoint(x: center.x - 16, y: center.y - 20))
    arrow.move(to: CGPoint(x: center.x + 16, y: center.y + 20))
    arrow.line(to: CGPoint(x: center.x + 36, y: center.y))
    arrow.line(to: CGPoint(x: center.x + 16, y: center.y - 20))
    color(0x4C6EF5).setStroke()
    arrow.stroke()

    // Subtle inner rim.
    color(0xFFFFFF, 0.25).setStroke()
    shape.lineWidth = 3
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appending(path: "icon_1024.png"))
print("wrote \(out)/icon_1024.png")
