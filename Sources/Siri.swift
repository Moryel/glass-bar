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
    @AppStorage("siriStyle") private var style = SiriStyle.liquid

    private static let ribbons: [RibbonView.Ribbon] = [
        .init(color: NSColor(srgbRed: 1, green: 0.37, blue: 0.66, alpha: 1), x: -0.16, y: -0.12, w: 0.62, h: 0.34, angle: 25),
        .init(color: NSColor(srgbRed: 0.25, green: 0.49, blue: 1, alpha: 1), x: 0.16, y: -0.04, w: 0.6, h: 0.32, angle: -40),
        .init(color: NSColor(srgbRed: 0.6, green: 0.36, blue: 1, alpha: 1), x: 0.02, y: 0.16, w: 0.64, h: 0.3, angle: 10),
        .init(color: NSColor(srgbRed: 1, green: 0.6, blue: 0.3, alpha: 1), x: -0.12, y: 0.12, w: 0.42, h: 0.24, angle: 70),
    ]

    var body: some View {
        if style == .liquid { mark } else { ribbonOrb }
    }

    private static let image = Bundle.main.url(forResource: "SiriOrb", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    /// The current logo, as an image.
    @ViewBuilder private var mark: some View {
        if let image = SiriOrb.image {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .brightness(isActive ? 0.08 : 0)
        } else {
            ribbonOrb
        }
    }

    private var ribbonOrb: some View {
        let b = size
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x1A1F45), Color(hex: 0x05060F)],
                                         center: .center, startRadius: 0, endRadius: b * 0.55))
            RibbonLayer(ribbons: SiriOrb.ribbons, isSpinning: isActive)
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
    static let isDemo = UserDefaults.standard.string(forKey: "testPanel") == "siriDemo"
    @ObservedObject private var microphone = Microphone.shared
    @StateObject private var smoother = Smoother()
    @StateObject private var motion = SiriMotion()
    @Environment(\.theme) private var theme
    @AppStorage("siriStyle") private var style = SiriStyle.liquid
    @AppStorage("siriBrightness") private var brightness = 1.0
    @AppStorage("siriFringe") private var fringe = 1.0
    @AppStorage("siriThinkingDots") private var thinkingDots = true

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // -testPanel siriDemo: a level that imitates speech without the microphone (for the README GIF)
            // the demo goes quiet for a few seconds in every ten so the thinking dots show too
            let target = SiriPill.isDemo ? (t.truncatingRemainder(dividingBy: 10) < 6.5 ? max(0, 0.55 * sin(t * 2.1) + 0.35 * sin(t * 5.3 + 1) + 0.15) : 0)
                : microphone.isRunning ? microphone.level : 0.2 + 0.12 * sin(t * 1.6)
            // the microphone value arrives in steps; it's smoothed every frame so the lines don't jitter
            if theme.isSkin {
                skinned(t, smoother.advance(target, t))
            } else if style == .classic {
                glass(t, smoother.advance(target, t))
            } else {
                liquid(t, motion.advance(target, t, thinks: thinkingDots))
            }
        }
    }

    private func liquid(_ t: Double, _ m: SiriMotion) -> some View {
        ZStack {
            GlassDrop()
            SiriLiquid(t: t, level: m.level, open: m.open, pull: m.pull, glow: brightness, fringe: fringe)
            Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.1), location: 0),
                                                          .init(color: .white.opacity(0.28), location: 0.5),
                                                          .init(color: .white.opacity(0.55), location: 1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
        }
        .frame(width: 300, height: Metrics.buttonHeight)
        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
    }

    /// In a skin: the theme's button with waves in the theme's colors, no glass.
    private func skinned(_ t: Double, _ level: Double) -> some View {
        let l = theme.layer(nil)
        let c = theme.waveColor
        return ZStack {
            // outline-only skins would show the receding buttons through the pill
            Rectangle().fill((theme.skin?.bar?.fill).flatMap { Color(hexString: $0) } ?? .black)
            SkinBackground()
            HStack(spacing: 4) {
                if l.border == "ascii" { Text(l.opening) }
                SiriWaves(t: t, level: level, palette: [c, c.opacity(0.6), c.opacity(0.35)], glows: false)
                if l.border == "ascii" { Text(l.closing) }
            }
            .font(theme.font(13)).foregroundStyle(l.text)
            .padding(.horizontal, 8).padding(.vertical, 2)
        }
        .frame(width: 300, height: Metrics.buttonHeight)
    }

    private func glass(_ t: Double, _ level: Double) -> some View {
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

enum SiriStyle: String, MenuOption {
    case liquid, classic
    var name: String {
        switch self {
        case .liquid: L("New")
        case .classic: L("Classic")
        }
    }
}

/// Level and state for the new drop. A spring follows the voice (quick rise with a little overshoot, quick fall);
/// once speech was heard and then stays silent for a while, the light pulls into the thinking dots.
final class SiriMotion: ObservableObject {
    private(set) var level = 0.0
    private(set) var open = 0.0
    private(set) var pull = 0.0
    private var velocity = 0.0, last = 0.0, start = 0.0, silence = 0.0
    private var heard = false, isThinking = false

    func advance(_ target: Double, _ t: Double, thinks: Bool) -> SiriMotion {
        if last == 0 { start = t }
        let dt = last == 0 ? 0 : min(0.1, max(0, t - last))
        last = t
        let n = max(1, Int((dt / 0.004).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n {
            velocity += (900 * (target - level) - 24 * velocity) * h
            level += velocity * h
        }
        level = min(1.25, max(0, level))
        let e = min(1, max(0, (t - start - 0.15) / 0.25))
        open = 1 - (1 - e) * (1 - e)

        if target > 0.25 { heard = true; silence = 0; isThinking = false }
        else if target < 0.06, heard { silence += dt }
        if thinks, silence > 1.2 { isThinking = true }
        pull += ((isThinking && thinks ? 1 : 0) - pull) * (1 - exp(-12 * dt))
        return self
    }
}

/// The inside of the new drop. Above the surface the glass is black, below it stays clear with a gray haze under the line.
/// The light is three thin sheets that cross each other; red, green and blue are drawn a little apart, so the sheets
/// are white where they overlap and get colored edges.
struct SiriLiquid: View {
    let t: Double
    let level: Double
    let open: Double
    let pull: Double
    var glow = 1.0
    var fringe = 1.0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, s = h * 1.6, mid = w / 2
            let l = level * (1 - pull), a = open * (1 - pull)
            let horizon = h * (0.56 + 0.05 * sin(2 * .pi * t / 6))
            let span = w - h * 0.9
            let cx = mid + span * 0.03 * sin(t * 0.55) * (1 - pull)
            let half = span / 2 * (1 - 0.8 * pull)
            let sag = h * 0.06

            func surface(_ x: Double) -> Double {
                let uu = (x - mid) / (w / 2), u = (x - cx) / half
                let env = abs(u) < 1 ? pow(1 - u * u, 1.25) : 0
                return horizon - sag * uu * uu + sag * 0.25 * uu * sin(t * 0.42) + s * 0.045 * l * sin(u * 2.4 + t * 3) * env
            }

            var line = Path()
            for x in stride(from: 0.0, through: w, by: 5) {
                let p = CGPoint(x: x, y: surface(x))
                x == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var above = line, below = line
            above.addLine(to: CGPoint(x: w, y: 0)); above.addLine(to: .zero); above.closeSubpath()
            below.addLine(to: CGPoint(x: w, y: h)); below.addLine(to: CGPoint(x: 0, y: h)); below.closeSubpath()
            ctx.fill(above, with: .color(.black.opacity(0.97)))
            ctx.fill(below, with: .linearGradient(Gradient(colors: [.black.opacity(0.3), .black.opacity(0.12)]),
                                                  startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
            ctx.blendMode = .plusLighter
            let haze = 0.3 * open * (0.55 + 0.45 * a) * (1 - 0.75 * pull)
            ctx.fill(below, with: .linearGradient(Gradient(colors: [Color(white: 0.8).opacity(haze), Color(white: 0.8).opacity(0)]),
                                                  startPoint: CGPoint(x: 0, y: horizon - sag), endPoint: CGPoint(x: 0, y: horizon + s * 0.22)))

            if a > 0.004 {
                let turn = 2 * .pi * t / 3, sw = 0.5 + 0.5 * sin(turn)
                let loud = min(1, l)
                let n = 40
                let ends = (CGPoint(x: cx - half, y: 0), CGPoint(x: cx + half, y: 0))

                // glow around the line
                let rx = half * 0.8, ry = s * (0.1 + 0.16 * l)
                var g = ctx
                g.translateBy(x: cx, y: horizon - ry * 0.15)
                g.scaleBy(x: 1, y: ry / rx)
                let tint = Color(red: 1 - 0.28 * sw, green: 0.86 + 0.02 * sw, blue: 0.7 + 0.3 * sw)
                g.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
                       with: .radialGradient(Gradient(colors: [tint.opacity(min(1, 0.22 * (1 + l) * a * glow)), tint.opacity(0)]),
                                             center: .zero, startRadius: 0, endRadius: rx))
                ctx.stroke(line, with: .color(.white.opacity(0.14 * a * glow)), lineWidth: 0.5)

                ctx.drawLayer { k in
                    k.addFilter(.blur(radius: 0.6))
                    k.blendMode = .plusLighter
                    for sheet in 0..<3 {
                        let fk = Double(sheet)
                        let phase = t * (1.7 + 0.5 * fk) + fk * 2.1
                        let m = sheet == 0 ? sw : 1 - sw      // outer sheets: one warm, one cool, trading places
                        let tints = sheet == 1 ? [1.0, 1, 1]
                            : [1 - 0.8 * (0.42 * m), 1 - 0.8 * (0.2 - 0.04 * m), 1 - 0.8 * (0.42 * (1 - m))]
                        for channel in 0..<3 {
                            let j = Double(channel) - 1
                            var top = [CGPoint](), bottom = [CGPoint](), stops = [Gradient.Stop]()
                            let amount = (0.6 - 0.27 * loud) * tints[channel] * (1 + 0.25 * loud) * a * glow
                            for i in 0...n {
                                let u = -1 + 2 * Double(i) / Double(n), x = cx + u * half
                                let env = pow(1 - u * u, 1.25), fat = pow(1 - u * u, 3.2 - loud)
                                let sway = sin(u * (2 + 0.7 * fk) + phase)
                                let swell = 0.5 + 0.5 * sin(u * 1.7 - phase * 0.7 + fk * 1.9)
                                let width = (s * (0.013 * fat + l * (0.014 + 0.062 * swell) * env * env) + 0.35) * 0.85
                                let c = surface(x) + s * (l * 0.06 * sway * env + (fk - 1) * l * 0.045 * sin(phase * 0.6) * env * env
                                    + j * fringe * (0.005 + 0.022 * l) * sin(u * 2.6 + turn + fk * 1.3) * env)
                                top.append(CGPoint(x: x, y: c - width)); bottom.append(CGPoint(x: x, y: c + width))
                                if i % 5 == 0 {
                                    let strength = pow(fat, 0.8) * (1 - loud) + env * loud
                                    let color = Color(red: channel == 0 ? 1 : 0, green: channel == 1 ? 1 : 0, blue: channel == 2 ? 1 : 0)
                                    stops.append(.init(color: color.opacity(min(1, amount * strength)), location: Double(i) / Double(n)))
                                }
                            }
                            var p = Path()
                            p.addLines(top + bottom.reversed())
                            p.closeSubpath()
                            k.fill(p, with: .linearGradient(Gradient(stops: stops), startPoint: ends.0, endPoint: ends.1))
                        }
                    }
                }
            }

            // thinking: four dots floating up and down one after another
            let dots = min(1, pull * 1.5) * glow
            if dots > 0.004 {
                let r = s * 0.04, y0 = h * 0.56
                for j in 0..<4 {
                    let fj = Double(j), beat = t * 4.2 - fj * 1.05
                    let c = CGPoint(x: mid + (fj - 1.5) * r * 4.8 * min(1, pull * 1.5), y: y0 + r * 1.5 * sin(beat))
                    let lift = (0.75 + 0.25 * cos(beat)) * min(1, dots)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.4 * lift), .white.opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: r * 3))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(lift)))
                }
            }
        }
        .clipShape(Capsule())
    }
}

/// Siri lines in the middle of the drop: thin, slowly flowing waves in the colors of the artwork, tapering toward the ends.
/// Almost flat when silent; each color rises a little differently as you speak.
struct SiriWaves: View {
    let t: Double
    let level: Double
    var palette = SiriWaves.colors
    /// soft glow under the lines (the glass look); skins draw only the lines
    var glows = true

    private static let colors: [Color] = [Color(hex: 0xFF6A3D), Color(hex: 0x3D8BFF), Color(hex: 0x9B5CFF),
                                           Color(hex: 0x34D399), .white]

    var body: some View {
        Canvas { ctx, size in
            let colors = palette
            let paths = colors.indices.map { path(i: $0, size: size) }
            guard glows else {
                for (i, p) in paths.enumerated() { ctx.stroke(p, with: .color(colors[i]), lineWidth: 1.4) }
                return
            }
            ctx.blendMode = .plusLighter
            ctx.drawLayer { k in
                k.addFilter(.blur(radius: 2.5))
                for (i, p) in paths.enumerated() { k.stroke(p, with: .color(colors[i].opacity(0.75)), lineWidth: 2.6) }
            }
            for (i, p) in paths.enumerated() {
                ctx.stroke(p, with: .color(colors[i].opacity(i == 4 ? 0.7 : 1)), lineWidth: i == 4 ? 0.8 : 1.2)
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
