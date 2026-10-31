// Draws the app icon: swift design/app_icon.swift <output.png> [size]
import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "icon.png"
let S = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let k = S / 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let c = NSGraphicsContext.current!.cgContext
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x*k, y: y*k, width: w*k, height: h*k) }
func color(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(h >> 16 & 255)/255, green: CGFloat(h >> 8 & 255)/255, blue: CGFloat(h & 255)/255, alpha: a)
}
let rgb = CGColorSpaceCreateDeviceRGB()
func linear(_ colors: [CGColor], _ a: CGPoint, _ b: CGPoint, _ locations: [CGFloat]? = nil) {
    c.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locations)!, start: a, end: b, options: [])
}
func glow(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ h: UInt32, _ a: CGFloat) {
    c.drawRadialGradient(CGGradient(colorsSpace: rgb, colors: [color(h, a), color(h, 0)] as CFArray, locations: nil)!,
                         startCenter: CGPoint(x: x*k, y: y*k), startRadius: 0, endCenter: CGPoint(x: x*k, y: y*k), endRadius: radius*k, options: [])
}

// Body: macOS icon grid (824 pt, corner 185)
let body = r(100, 100, 824, 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185*k, cornerHeight: 185*k, transform: nil)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -10*k), blur: 28*k, color: color(0, 0.45))
c.addPath(bodyPath); c.setFillColor(color(0x0B0E1A)); c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(bodyPath); c.clip()
linear([color(0x1A2140), color(0x07080F)], CGPoint(x: 0, y: 924*k), CGPoint(x: 0, y: 100*k))
// Ambient background lights (aurora)
glow(300, 760, 420, 0x3D8BFF, 0.55)
glow(760, 720, 380, 0x9B5CFF, 0.45)
glow(720, 260, 380, 0xFF6A3D, 0.35)
glow(260, 280, 340, 0x34D399, 0.25)

// Touch Bar strip: glass capsule
let strip = r(150, 432, 724, 160)
let stripPath = CGPath(roundedRect: strip, cornerWidth: 80*k, cornerHeight: 80*k, transform: nil)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14*k), blur: 34*k, color: color(0, 0.6))
c.addPath(stripPath); c.setFillColor(color(0x05060C, 0.82)); c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(stripPath); c.clip()
linear([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0.03), color(0xFFFFFF, 0.08)],
         CGPoint(x: 0, y: strip.maxY), CGPoint(x: 0, y: strip.minY), [0, 0.55, 1])

// Glass keys on the left
for (i, x) in [196, 296].enumerated() {
    let key = r(CGFloat(x), 470, 84, 84)
    let path = CGPath(roundedRect: key, cornerWidth: 22*k, cornerHeight: 22*k, transform: nil)
    c.addPath(path); c.setFillColor(color(0xFFFFFF, i == 0 ? 0.20 : 0.14)); c.fillPath()
    c.saveGState(); c.addPath(path); c.clip()
    linear([color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)], CGPoint(x: 0, y: key.maxY), CGPoint(x: 0, y: key.midY))
    c.restoreGState()
}

// Siri wave: colorful lines
let waveLeft: CGFloat = 420, waveRight: CGFloat = 830, mid: CGFloat = 512
let lines: [(UInt32, CGFloat, CGFloat, CGFloat)] = [
    (0x3D8BFF, 1.0, 0.0, 1.6), (0x9B5CFF, 0.8, 1.3, 2.1), (0xFF6A3D, 0.7, 2.4, 1.3), (0x34D399, 0.55, 3.6, 2.6), (0xFFFFFF, 0.45, 0.7, 1.9)]
c.setBlendMode(.screen)
for (h, strength, phase, frequency) in lines {
    let path = CGMutablePath()
    var x = waveLeft
    while x <= waveRight {
        let u = (x - waveLeft) / (waveRight - waveLeft)
        let envelope = pow(sin(.pi * u), 2)
        let y = mid + 52 * strength * envelope * sin(u * .pi * 2 * frequency + phase)
        x == waveLeft ? path.move(to: CGPoint(x: x*k, y: y*k)) : path.addLine(to: CGPoint(x: x*k, y: y*k))
        x += 2
    }
    c.saveGState()
    c.setShadow(offset: .zero, blur: 14*k, color: color(h, 0.9))
    c.addPath(path); c.setStrokeColor(color(h, h == 0xFFFFFF ? 0.85 : 0.95)); c.setLineWidth(7*k); c.setLineCap(.round); c.strokePath()
    c.restoreGState()
}
c.setBlendMode(.normal)
c.restoreGState()

// Strip edge: bright at the top, dim at the bottom
c.saveGState()
c.addPath(stripPath); c.setLineWidth(3*k); c.replacePathWithStrokedPath(); c.clip()
linear([color(0xFFFFFF, 0.75), color(0xFFFFFF, 0.08), color(0xFFFFFF, 0.35)], CGPoint(x: 0, y: strip.maxY), CGPoint(x: 0, y: strip.minY), [0, 0.5, 1])
c.restoreGState()
c.restoreGState()

// Body edge: thin glass shine
c.saveGState()
c.addPath(bodyPath); c.setLineWidth(4*k); c.replacePathWithStrokedPath(); c.clip()
linear([color(0xFFFFFF, 0.45), color(0xFFFFFF, 0.04), color(0xFFFFFF, 0.18)], CGPoint(x: 0, y: body.maxY), CGPoint(x: 0, y: body.minY), [0, 0.5, 1])
c.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
