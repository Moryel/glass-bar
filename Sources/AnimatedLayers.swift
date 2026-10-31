import AppKit
import QuartzCore
import SwiftUI

// Continuously rotating/swaying background animations live in Core Animation: the window server plays them,
// the app does no work per frame (in SwiftUI, repeatForever updates the body every frame).

/// Soft-edged color blob: a radial gradient instead of a blur, essentially free.
private func glowBlob(_ color: NSColor) -> CAGradientLayer {
    let g = CAGradientLayer()
    g.type = .radial
    g.startPoint = CGPoint(x: 0.5, y: 0.5)
    g.endPoint = CGPoint(x: 1, y: 1)
    setBlobColor(g, color)
    return g
}

private func setBlobColor(_ g: CAGradientLayer, _ color: NSColor) {
    g.colors = [color.cgColor, color.withAlphaComponent(0.5).cgColor, color.withAlphaComponent(0).cgColor]
    g.locations = [0, 0.4, 1]
}

/// Three lights drifting slowly behind the glass in the app's color.
final class AmbientView: NSView {
    private let blobs: [CAGradientLayer] = (0..<3).map { _ in glowBlob(.systemBlue) }
    private let opacities: [Float] = [0.42, 0.26, 0.32]
    private var lastSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (i, l) in blobs.enumerated() {
            l.opacity = opacities[i]
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        let w = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, l) in blobs.enumerated() {
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
            l.add(a, forKey: "sway")
        }
        CATransaction.commit()
    }

    func colors(_ r: [NSColor]) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        for (i, l) in blobs.enumerated() { setBlobColor(l, r[i % r.count]) }
        CATransaction.commit()
    }
}

struct AmbientLayer: NSViewRepresentable {
    let colors: [NSColor]
    func makeNSView(context: Context) -> AmbientView { AmbientView() }
    func updateNSView(_ v: AmbientView, context: Context) { v.colors(colors) }
}

/// Light ribbons spinning inside the Siri orb.
final class RibbonView: NSView {
    struct Ribbon { let color: NSColor; let x, y, w, h: CGFloat; let angle: CGFloat }
    private let container = CALayer()
    private var lastSize: CGSize = .zero
    var ribbons: [Ribbon] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(container)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        let b = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        container.bounds = bounds
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for k in ribbons {
            let l = glowBlob(k.color)
            l.bounds = CGRect(x: 0, y: 0, width: b * k.w * 1.5, height: b * k.h * 1.5)
            l.position = CGPoint(x: b / 2 + b * k.x, y: b / 2 + b * k.y)
            l.setAffineTransform(CGAffineTransform(rotationAngle: k.angle * .pi / 180))
            container.addSublayer(l)
        }
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = -2 * Double.pi
        a.duration = 8
        a.repeatCount = .infinity
        container.add(a, forKey: "spin")
        CATransaction.commit()
    }
}

struct RibbonLayer: NSViewRepresentable {
    let ribbons: [RibbonView.Ribbon]
    func makeNSView(context: Context) -> RibbonView {
        let v = RibbonView()
        v.ribbons = ribbons
        return v
    }
    func updateNSView(_ v: RibbonView, context: Context) {}
}
