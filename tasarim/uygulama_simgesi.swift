// Uygulama simgesini çizer: swift tasarim/uygulama_simgesi.swift <çıktı.png> [boyut]
import AppKit

let args = CommandLine.arguments
let cikti = args.count > 1 ? args[1] : "simge.png"
let S = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let k = S / 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let c = NSGraphicsContext.current!.cgContext
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x*k, y: y*k, width: w*k, height: h*k) }
func renk(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(h >> 16 & 255)/255, green: CGFloat(h >> 8 & 255)/255, blue: CGFloat(h & 255)/255, alpha: a)
}
let rgb = CGColorSpaceCreateDeviceRGB()
func dogrusal(_ renkler: [CGColor], _ a: CGPoint, _ b: CGPoint, _ yerler: [CGFloat]? = nil) {
    c.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: renkler as CFArray, locations: yerler)!, start: a, end: b, options: [])
}
func isik(_ x: CGFloat, _ y: CGFloat, _ yaricap: CGFloat, _ h: UInt32, _ a: CGFloat) {
    c.drawRadialGradient(CGGradient(colorsSpace: rgb, colors: [renk(h, a), renk(h, 0)] as CFArray, locations: nil)!,
                         startCenter: CGPoint(x: x*k, y: y*k), startRadius: 0, endCenter: CGPoint(x: x*k, y: y*k), endRadius: yaricap*k, options: [])
}

// Gövde: macOS simge ızgarası (824 pt, köşe 185)
let govde = r(100, 100, 824, 824)
let govdeYol = CGPath(roundedRect: govde, cornerWidth: 185*k, cornerHeight: 185*k, transform: nil)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -10*k), blur: 28*k, color: renk(0, 0.45))
c.addPath(govdeYol); c.setFillColor(renk(0x0B0E1A)); c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(govdeYol); c.clip()
dogrusal([renk(0x1A2140), renk(0x07080F)], CGPoint(x: 0, y: 924*k), CGPoint(x: 0, y: 100*k))
// Arka plan ortam ışıkları (aurora)
isik(300, 760, 420, 0x3D8BFF, 0.55)
isik(760, 720, 380, 0x9B5CFF, 0.45)
isik(720, 260, 380, 0xFF6A3D, 0.35)
isik(260, 280, 340, 0x34D399, 0.25)

// Touch Bar şeridi: cam kapsül
let serit = r(150, 432, 724, 160)
let seritYol = CGPath(roundedRect: serit, cornerWidth: 80*k, cornerHeight: 80*k, transform: nil)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14*k), blur: 34*k, color: renk(0, 0.6))
c.addPath(seritYol); c.setFillColor(renk(0x05060C, 0.82)); c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(seritYol); c.clip()
dogrusal([renk(0xFFFFFF, 0.16), renk(0xFFFFFF, 0.03), renk(0xFFFFFF, 0.08)],
         CGPoint(x: 0, y: serit.maxY), CGPoint(x: 0, y: serit.minY), [0, 0.55, 1])

// Soldaki cam tuşlar
for (i, x) in [196, 296].enumerated() {
    let tus = r(CGFloat(x), 470, 84, 84)
    let yol = CGPath(roundedRect: tus, cornerWidth: 22*k, cornerHeight: 22*k, transform: nil)
    c.addPath(yol); c.setFillColor(renk(0xFFFFFF, i == 0 ? 0.20 : 0.14)); c.fillPath()
    c.saveGState(); c.addPath(yol); c.clip()
    dogrusal([renk(0xFFFFFF, 0.28), renk(0xFFFFFF, 0)], CGPoint(x: 0, y: tus.maxY), CGPoint(x: 0, y: tus.midY))
    c.restoreGState()
}

// Siri dalgası: renkli çizgiler
let dalgaSol: CGFloat = 420, dalgaSag: CGFloat = 830, orta: CGFloat = 512
let cizgiler: [(UInt32, CGFloat, CGFloat, CGFloat)] = [
    (0x3D8BFF, 1.0, 0.0, 1.6), (0x9B5CFF, 0.8, 1.3, 2.1), (0xFF6A3D, 0.7, 2.4, 1.3), (0x34D399, 0.55, 3.6, 2.6), (0xFFFFFF, 0.45, 0.7, 1.9)]
c.setBlendMode(.screen)
for (h, guc, faz, frek) in cizgiler {
    let yol = CGMutablePath()
    var x = dalgaSol
    while x <= dalgaSag {
        let u = (x - dalgaSol) / (dalgaSag - dalgaSol)
        let zarf = pow(sin(.pi * u), 2)
        let y = orta + 52 * guc * zarf * sin(u * .pi * 2 * frek + faz)
        x == dalgaSol ? yol.move(to: CGPoint(x: x*k, y: y*k)) : yol.addLine(to: CGPoint(x: x*k, y: y*k))
        x += 2
    }
    c.saveGState()
    c.setShadow(offset: .zero, blur: 14*k, color: renk(h, 0.9))
    c.addPath(yol); c.setStrokeColor(renk(h, h == 0xFFFFFF ? 0.85 : 0.95)); c.setLineWidth(7*k); c.setLineCap(.round); c.strokePath()
    c.restoreGState()
}
c.setBlendMode(.normal)
c.restoreGState()

// Şerit kenarı: üstte parlak, altta sönük
c.saveGState()
c.addPath(seritYol); c.setLineWidth(3*k); c.replacePathWithStrokedPath(); c.clip()
dogrusal([renk(0xFFFFFF, 0.75), renk(0xFFFFFF, 0.08), renk(0xFFFFFF, 0.35)], CGPoint(x: 0, y: serit.maxY), CGPoint(x: 0, y: serit.minY), [0, 0.5, 1])
c.restoreGState()
c.restoreGState()

// Gövde kenarı: ince cam parıltısı
c.saveGState()
c.addPath(govdeYol); c.setLineWidth(4*k); c.replacePathWithStrokedPath(); c.clip()
dogrusal([renk(0xFFFFFF, 0.45), renk(0xFFFFFF, 0.04), renk(0xFFFFFF, 0.18)], CGPoint(x: 0, y: govde.maxY), CGPoint(x: 0, y: govde.minY), [0, 0.5, 1])
c.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: cikti))
