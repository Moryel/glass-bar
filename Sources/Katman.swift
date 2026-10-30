import AppKit
import QuartzCore
import SwiftUI

// Sürekli dönen/salınan arka plan animasyonları Core Animation'da: pencere sunucusu oynatır,
// uygulama her karede iş yapmaz (SwiftUI'da repeatForever her karede gövde günceller).

/// Yumuşak kenarlı renk lekesi: bulanıklık yerine dairesel geçiş, maliyetsiz.
private func leke(_ renk: NSColor) -> CAGradientLayer {
    let g = CAGradientLayer()
    g.type = .radial
    g.startPoint = CGPoint(x: 0.5, y: 0.5)
    g.endPoint = CGPoint(x: 1, y: 1)
    lekeRengi(g, renk)
    return g
}

private func lekeRengi(_ g: CAGradientLayer, _ renk: NSColor) {
    g.colors = [renk.cgColor, renk.withAlphaComponent(0.5).cgColor, renk.withAlphaComponent(0).cgColor]
    g.locations = [0, 0.4, 1]
}

/// Camın arkasında uygulamanın renginde yavaşça dolaşan üç ışık.
final class OrtamGorunum: NSView {
    private let lekeler: [CAGradientLayer] = (0..<3).map { _ in leke(.systemBlue) }
    private let opaklik: [Float] = [0.42, 0.26, 0.32]
    private var boyut: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (i, l) in lekeler.enumerated() {
            l.opacity = opaklik[i]
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != boyut, bounds.width > 0 else { return }
        boyut = bounds.size
        let w = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, l) in lekeler.enumerated() {
            let d = CGFloat(i)
            let x = w * (0.08 + 0.36 * d) + w * 0.15
            l.bounds = CGRect(x: 0, y: 0, width: w * 0.46, height: 110)
            l.position = CGPoint(x: x, y: bounds.midY)
            let a = CABasicAnimation(keyPath: "position.x")
            a.fromValue = x - w * 0.12
            a.toValue = x + w * 0.12
            a.duration = 7 + Double(i) * 2.5
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.timeOffset = Double(i) * 3
            l.add(a, forKey: "salinim")
        }
        CATransaction.commit()
    }

    func renkler(_ r: [NSColor]) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        for (i, l) in lekeler.enumerated() { lekeRengi(l, r[i % r.count]) }
        CATransaction.commit()
    }
}

struct OrtamKatmani: NSViewRepresentable {
    let renkler: [NSColor]
    func makeNSView(context: Context) -> OrtamGorunum { OrtamGorunum() }
    func updateNSView(_ v: OrtamGorunum, context: Context) { v.renkler(renkler) }
}

/// Siri küresinin içinde dönen ışık kurdeleleri.
final class KurdeleGorunum: NSView {
    struct Kurdele { let renk: NSColor; let x, y, w, h: CGFloat; let aci: CGFloat }
    private let kap = CALayer()
    private var boyut: CGSize = .zero
    var kurdeleler: [Kurdele] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(kap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != boyut, bounds.width > 0 else { return }
        boyut = bounds.size
        let b = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        kap.sublayers?.forEach { $0.removeFromSuperlayer() }
        kap.bounds = bounds
        kap.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for k in kurdeleler {
            let l = leke(k.renk)
            l.bounds = CGRect(x: 0, y: 0, width: b * k.w * 1.5, height: b * k.h * 1.5)
            l.position = CGPoint(x: b / 2 + b * k.x, y: b / 2 + b * k.y)
            l.setAffineTransform(CGAffineTransform(rotationAngle: k.aci * .pi / 180))
            kap.addSublayer(l)
        }
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = -2 * Double.pi
        a.duration = 8
        a.repeatCount = .infinity
        kap.add(a, forKey: "donme")
        CATransaction.commit()
    }
}

struct KurdeleKatmani: NSViewRepresentable {
    let kurdeleler: [KurdeleGorunum.Kurdele]
    func makeNSView(context: Context) -> KurdeleGorunum {
        let v = KurdeleGorunum()
        v.kurdeleler = kurdeleler
        return v
    }
    func updateNSView(_ v: KurdeleGorunum, context: Context) {}
}
