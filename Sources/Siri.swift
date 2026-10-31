import SwiftUI

// The iOS 27 Siri: no edge glow; a dark Liquid Glass orb drifts in and pulses gently,
// and the wave inside, the only element carrying Siri's old colors, moves with the voice. The colors are WWDC26's soft
// pink, deep blue, purple and orange.
enum SiriColors {
    static let pink = Color(hex: 0xE98DBF)
    static let indigo = Color(hex: 0x3D5AD6)
    static let purple = Color(hex: 0x8C6FE8)
    static let orange = Color(hex: 0xF0A066)
    static let all = [pink, indigo, purple, orange]
    static let glass = Color(hex: 0x10132A)
}

/// The Siri logo in the Control Strip: light ribbons in pink, blue, purple and orange slowly spinning and blending
/// inside a dark glass orb; a white core in the middle and a glass highlight on top.
struct SiriOrb: View {
    var isActive = false
    var size: CGFloat = 21

    private static let ribbons: [RibbonView.Ribbon] = [
        .init(color: NSColor(srgbRed: 1, green: 0.37, blue: 0.66, alpha: 1), x: -0.16, y: -0.12, w: 0.62, h: 0.34, angle: 25),
        .init(color: NSColor(srgbRed: 0.25, green: 0.49, blue: 1, alpha: 1), x: 0.16, y: -0.04, w: 0.6, h: 0.32, angle: -40),
        .init(color: NSColor(srgbRed: 0.6, green: 0.36, blue: 1, alpha: 1), x: 0.02, y: 0.16, w: 0.64, h: 0.3, angle: 10),
        .init(color: NSColor(srgbRed: 1, green: 0.6, blue: 0.3, alpha: 1), x: -0.12, y: 0.12, w: 0.42, h: 0.24, angle: 70),
    ]

    var body: some View {
        let b = size
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x1A1F45), Color(hex: 0x05060F)],
                                         center: .center, startRadius: 0, endRadius: b * 0.55))
            RibbonLayer(ribbons: SiriOrb.ribbons)
                .blendMode(.plusLighter)
            // bright core
            Circle().fill(RadialGradient(colors: [.white.opacity(isActive ? 0.75 : 0.5), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: b * 0.24))
                .blendMode(.plusLighter)
            // glass edge and highlight
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04), .white.opacity(0.22)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: b * 0.55, height: b * 0.28)
                .offset(y: -b * 0.26)
        }
        .frame(width: b, height: b)
        .clipShape(Circle())
        .shadow(color: Color(hex: 0x9A5CFF).opacity(isActive ? 0.75 : 0.35), radius: isActive ? 6 : 3)
    }
}

/// A pill floating in the middle of the app area while listening, like Apple's new Siri: a clear Liquid Glass drop
/// flowing out of the Dynamic Island. It magnifies and refracts the bar behind it (real glass on macOS 26), its dark refraction ring and
/// bright inner line make it look like glass; colored Siri lines flow through the middle. The lines rise as you speak and the drop
/// swells slightly like jelly.
struct SiriPill: View {
    static let isDemo = UserDefaults.standard.string(forKey: "tb2kip") == "siriDemo"
    @ObservedObject private var microphone = Microphone.shared
    @StateObject private var smoother = Smoother()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // -tb2kip siriDemo: a level that imitates speech without the microphone (for the README GIF)
            let target = SiriPill.isDemo ? max(0, 0.55 * sin(t * 2.1) + 0.35 * sin(t * 5.3 + 1) + 0.15)
                : microphone.isRunning ? microphone.level : 0.2 + 0.12 * sin(t * 1.6)
            // the microphone value arrives in steps; it's smoothed every frame so the lines don't jitter
            let level = smoother.advance(target, t)
            ZStack {
                GlassDrop()
                SiriWaves(t: t, level: level)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.2),
                                                 .init(color: .white, location: 0.8), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, 14).padding(.vertical, 2)
                // refraction ring: the glass edge darkens because it refracts what's behind
                Capsule().strokeBorder(.black.opacity(0.45), lineWidth: 3).blur(radius: 1.5).clipShape(Capsule())
                // bright inner line: catches the light at the top and bottom
                Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                                              .init(color: .white.opacity(0.12), location: 0.45),
                                                              .init(color: .white.opacity(0.5), location: 1)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
                    .padding(1.2)
                // specular highlight at the top left
                Ellipse().fill(.white.opacity(0.35)).frame(width: 70, height: 6).blur(radius: 3)
                    .offset(x: -80, y: -7)
            }
            .frame(width: 300, height: Metrics.buttonHeight)
            .scaleEffect(x: 1 + 0.035 * level, y: 1 + 0.07 * level)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
        }
    }
}

/// Per-frame smoothing: approaches the target exponentially based on frame time (fast rise, slow fall).
final class Smoother: ObservableObject {
    private var value = 0.0
    private var lastTime = 0.0

    func advance(_ target: Double, _ t: Double) -> Double {
        let dt = lastTime == 0 ? 0 : min(0.1, max(0, t - lastTime))
        lastTime = t
        let k = target > value ? 9.0 : 3.5
        value += (target - value) * (1 - exp(-k * dt))
        return value
    }
}

/// Siri lines in the middle of the drop: thin, slowly flowing waves in the colors of the artwork, tapering toward the ends.
/// Almost flat when silent; each color rises a little differently as you speak.
struct SiriWaves: View {
    let t: Double
    let level: Double

    private static let colors: [Color] = [Color(hex: 0xFF6A3D), Color(hex: 0x3D8BFF), Color(hex: 0x9B5CFF),
                                           Color(hex: 0x34D399), .white]

    var body: some View {
        Canvas { ctx, size in
            let paths = SiriWaves.colors.indices.map { path(i: $0, size: size) }
            ctx.blendMode = .plusLighter
            ctx.drawLayer { k in
                k.addFilter(.blur(radius: 2.5))
                for (i, p) in paths.enumerated() { k.stroke(p, with: .color(SiriWaves.colors[i].opacity(0.75)), lineWidth: 2.6) }
            }
            for (i, p) in paths.enumerated() {
                ctx.stroke(p, with: .color(SiriWaves.colors[i].opacity(i == 4 ? 0.7 : 1)), lineWidth: i == 4 ? 0.8 : 1.2)
            }
        }
    }

    private func path(i: Int, size: CGSize) -> Path {
        let d = Double(i)
        // each line with its own slow rhythm; all rise with the voice
        let rhythm = 0.55 + 0.45 * sin(t * (0.9 + 0.17 * d) + d * 1.7)
        let amplitude = size.height * 0.42 * (0.05 + 0.95 * level) * rhythm
        let frequency = 1.1 + d * 0.35, phase = t * (1.6 + d * 0.35) + d
        var p = Path()
        for x in stride(from: 0.0, through: size.width, by: 1) {
            let envelope = pow(sin(.pi * x / size.width), 2.2)
            let y = size.height / 2 + sin(x / size.width * .pi * 2 * frequency + phase) * amplitude * envelope
            x == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
        }
        return p
    }
}

/// The drop's glass: Apple's real Liquid Glass on macOS 26 (magnifies and refracts what's behind), light frosted glass before that.
struct GlassDrop: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(.white.opacity(0.04)))
        }
    }
}

/// The orb drifting in like a drop from the Siri button on the right.
struct DropIn: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.06 + 0.94 * p, y: 0.7 + 0.3 * p, anchor: .trailing)
            .offset(x: (1 - p) * 220)
            .blur(radius: (1 - p) * 5)
            .opacity(min(1, p * 1.6))
    }
}

extension AnyTransition {
    static var dropIn: AnyTransition { .modifier(active: DropIn(p: 0), identity: DropIn(p: 1)) }
}
