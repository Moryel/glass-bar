// Draws the app icon: swift design/app_icon.swift <output.png> [size]
// A Touch Bar showing four themes (glass, neon, terminal, arcade) above two rows of keys.
import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "icon.png"
let size = args.count > 2 ? Int(args[2])! : 1024
let k = CGFloat(size) / 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * k, y: y * k, width: w * k, height: h * k) }
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius * k, yRadius: radius * k) }
func glow(_ hex: UInt32, _ alpha: CGFloat, _ blur: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur * k
    shadow.shadowColor = color(hex, alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824 pt body, corner 185
let body = r(100, 100, 824, 824)
let bodyPath = rounded(body, 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28 * k
shadow.shadowOffset = NSSize(width: 0, height: -12 * k)
shadow.set()
color(0x16161A).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

bodyPath.addClip()
NSGradient(starting: color(0x3A3A3F), ending: color(0x16161A))!.draw(in: body, angle: -90)

let strip = r(130, 560, 764, 190)
let stripPath = rounded(strip, 40)
color(0x000000).setFill()
stripPath.fill()
color(0xFFFFFF, 0.10).setStroke()
stripPath.lineWidth = 4 * k
stripPath.stroke()

let segment: CGFloat = (764 - 60 - 3 * 16) / 4
func slot(_ i: Int) -> NSRect { r(160 + CGFloat(i) * (segment + 16), 590, segment, 130) }

// glass
let glass = slot(0)
let glassPath = rounded(glass, 28)
NSGradient(starting: color(0x4FC3F7, 0.70), ending: color(0x4FC3F7, 0.18))!.draw(in: glassPath, angle: -90)
NSGraphicsContext.saveGraphicsState()
glassPath.addClip()
NSGradient(starting: NSColor.white.withAlphaComponent(0.45), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: NSRect(x: glass.minX, y: glass.midY + glass.height * 0.1, width: glass.width, height: glass.height * 0.4), angle: -90)
NSGraphicsContext.restoreGraphicsState()
color(0xFFFFFF, 0.35).setStroke()
glassPath.lineWidth = 3 * k
glassPath.stroke()

// neon
let neon = rounded(slot(1).insetBy(dx: 6 * k, dy: 6 * k), 28)
neon.lineWidth = 8 * k
glow(0xE36BD8, 1, 26) { color(0xFF6FE6).setStroke(); neon.stroke() }

// terminal
let terminal = slot(2)
let terminalPath = rounded(terminal, 14)
color(0x07140A).setFill()
terminalPath.fill()
color(0x7BE08A, 0.5).setStroke()
terminalPath.lineWidth = 3 * k
terminalPath.stroke()
let caret = NSBezierPath()
caret.move(to: NSPoint(x: terminal.minX + 40 * k, y: terminal.midY + 30 * k))
caret.line(to: NSPoint(x: terminal.minX + 75 * k, y: terminal.midY))
caret.line(to: NSPoint(x: terminal.minX + 40 * k, y: terminal.midY - 30 * k))
caret.lineWidth = 12 * k
caret.lineCapStyle = .square
glow(0x7BE08A, 0.9, 14) {
    color(0x7BE08A).setStroke()
    caret.stroke()
    color(0x7BE08A).setFill()
    NSBezierPath(rect: NSRect(x: terminal.minX + 92 * k, y: terminal.midY - 32 * k, width: 40 * k, height: 12 * k)).fill()
}

// arcade
let arcade = slot(3)
color(0x1B0F3A).setFill()
NSBezierPath(rect: arcade).fill()
let pixel = 16 * k
let sprite = ["0000110000", "0000110000", "0111111110", "0100110010", "1111111111", "0110000110", "0111111110", "0010000100"]
let origin = NSPoint(x: arcade.midX - 5 * pixel, y: arcade.midY + 4 * pixel)
glow(0xFFC53D, 0.8, 12) {
    color(0xFFC53D).setFill()
    for (row, line) in sprite.enumerated() {
        for (col, bit) in line.enumerated() where bit == "1" {
            NSBezierPath(rect: NSRect(x: origin.x + CGFloat(col) * pixel, y: origin.y - CGFloat(row + 1) * pixel,
                                      width: pixel, height: pixel)).fill()
        }
    }
}

// two rows of keys, the lower one shifted like a keyboard
for row in 0..<2 {
    for i in 0..<5 {
        let x = 130 + CGFloat(i) * 178 - (row == 1 ? 60 : 0)
        let key = rounded(r(x, 380 - CGFloat(row) * 158, 150, 130), 22)
        color(0x0E0E10).setFill()
        key.fill()
        color(0xFFFFFF, 0.06).setStroke()
        key.lineWidth = 3 * k
        key.stroke()
    }
}

NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
