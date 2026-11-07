import AppKit
import CoreText
import SwiftUI

// A skin draws every part of the bar without glass: a terminal with ASCII brackets, pixel art, paper…
// It lives in a theme's "skin" key; all fields are optional, so a skin only states what it changes.

/// Look of a button, a group or a role; every field is optional so it can patch another layer.
struct LayerPatch: Codable, Equatable {
    /// "#RRGGBB(AA)" or "none"
    var fill: String? = nil
    /// second color: a top-to-bottom gradient from `fill`
    var fill2: String? = nil
    var text: String? = nil
    /// none, solid, dashed, pixel, ascii, sketch
    var border: String? = nil
    var borderWidth: Double? = nil
    var borderColor: String? = nil
    var radius: Double? = nil
    var glow: Double? = nil
    var glowColor: String? = nil
    var shadow: Double? = nil
    /// pixel border: light top-left and dark bottom-right edges
    var bevel: Bool? = nil
    /// ASCII border: opening and closing characters, separated by a space ("[ ]", "< >", "| |")
    var chars: String? = nil
    /// swap the fill and text colors (a pressed terminal key)
    var invert: Bool? = nil
}

struct Skin: Codable, Equatable {
    var bar: BarStyle? = nil
    var button: LayerPatch? = nil
    /// changes while a button is pressed
    var pressed: LayerPatch? = nil
    /// the background of a button group
    var group: LayerPatch? = nil
    var text: TextStyle? = nil
    /// Apple symbol name → text ("chevron.left": "<") or "image:file.png" from the package
    var icons: [String: String]? = nil
    /// liquid, pop, shake, wobble, none
    var press: String? = nil
    /// "tap" → a sound file in the package, or a built-in sound: click, blip, tick
    var sounds: [String: String]? = nil
}

struct BarStyle: Codable, Equatable {
    var fill: String? = nil
    var fill2: String? = nil
    /// background pattern: stars, grid
    var pattern: String? = nil
    var patternColor: String? = nil
    /// drawn over everything: scanlines
    var overlay: String? = nil
}

struct TextStyle: Codable, Equatable {
    /// a font file in the package (.ttf/.otf), an installed font name, or system, mono, rounded, serif
    var font: String? = nil
    /// multiplies every text size
    var scale: Double? = nil
    var weight: String? = nil
    /// upper, lower
    var letterCase: String? = nil
    var tracking: Double? = nil

    enum CodingKeys: String, CodingKey { case font, scale, weight, letterCase = "case", tracking }
}

enum PressEffect: String { case liquid, pop, shake, wobble, none }

/// A layer with every value filled in.
struct ResolvedLayer {
    var fill: Color? = nil
    var fill2: Color? = nil
    var text = Color.white
    var border = "none"
    var borderWidth: CGFloat = 1
    var borderColor = Color.white
    var radius: CGFloat = 6
    var glow: CGFloat = 0
    var glowColor = Color.white
    var shadow: CGFloat = 0
    var bevel = false
    var opening = "["
    var closing = "]"

    mutating func apply(_ p: LayerPatch?) {
        guard let p else { return }
        if let f = p.fill { fill = f == "none" ? nil : Color(hexString: f) ?? fill }
        if let f = p.fill2 { fill2 = Color(hexString: f) }
        if let c = p.text.flatMap(Color.init(hexString:)) { text = c }
        if let b = p.border { border = b }
        if let w = p.borderWidth { borderWidth = w }
        if let c = p.borderColor.flatMap(Color.init(hexString:)) { borderColor = c }
        if let r = p.radius { radius = r }
        if let g = p.glow { glow = g }
        if let c = p.glowColor.flatMap(Color.init(hexString:)) { glowColor = c }
        if let s = p.shadow { shadow = s }
        if let b = p.bevel { bevel = b }
        if let c = p.chars {
            let parts = c.split(separator: " ", maxSplits: 1).map(String.init)
            opening = parts.first ?? ""
            closing = parts.count > 1 ? parts[1] : ""
        }
        if p.invert == true {
            let t = text
            text = fill ?? .black
            fill = t
            fill2 = nil
        }
    }
}

extension Theme {
    var isSkin: Bool { skin != nil }
    /// Text drawn straight on the bar (track names, times): in a skin the button fill (the button text is meant for the fill),
    /// or the button text when buttons have no fill.
    var barText: Color { isSkin ? (layer(nil).fill ?? layer(nil).text) : text }
    /// Waves and sound bars: the slider color, else the bar text.
    var waveColor: Color { sliderFill ?? barText }

    /// The look of a button for a role, pressed or not.
    func layer(_ role: Role?, pressed: Bool = false) -> ResolvedLayer {
        var l = ResolvedLayer()
        l.text = text
        l.borderColor = text
        l.apply(skin?.button)
        if let k = role?.key { l.apply(roles[k] ?? roles[Role.fallback(k)]) }
        if case .custom(let c) = role { l.fill = c }
        if pressed { l.apply(skin?.pressed) }
        return l
    }

    func groupLayer(_ role: Role?) -> ResolvedLayer {
        var l = layer(nil)
        l.apply(skin?.group)
        if let k = role?.key { l.apply(roles[k]) }
        return l
    }

    /// Groups are drawn as separate buttons when the border can't be shared (ASCII brackets, pixel edges).
    var splitsGroups: Bool { isSkin && ["ascii", "pixel"].contains(layer(nil).border) }

    var pressEffect: PressEffect { PressEffect(rawValue: skin?.press ?? "") ?? (isSkin ? .pop : .liquid) }

    var textScale: CGFloat { CGFloat(skin?.text?.scale ?? 1) }

    var letterCase: Text.Case? {
        switch skin?.text?.letterCase {
        case "upper": .uppercase
        case "lower": .lowercase
        default: nil
        }
    }

    var tracking: CGFloat { CGFloat(skin?.text?.tracking ?? 0) }

    /// The font for a size in the built-in look; a skin's font and scale apply.
    func font(_ size: CGFloat, _ weight: Font.Weight? = nil) -> Font {
        let s = size * textScale, w = weight ?? self.weight
        guard let f = skin?.text?.font, !f.isEmpty else { return .system(size: s, weight: w, design: design) }
        switch f {
        case "system": return .system(size: s, weight: w)
        case "mono": return .system(size: s, weight: w, design: .monospaced)
        case "rounded": return .system(size: s, weight: w, design: .rounded)
        case "serif": return .system(size: s, weight: w, design: .serif)
        default: return .custom(ThemeFonts.name(f, base: baseURL), size: s).weight(w)
        }
    }

    /// The same font in AppKit, for measuring text.
    func nsFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let s = size * textScale
        switch skin?.text?.font ?? "" {
        case "", "system", "rounded", "serif": return .systemFont(ofSize: s, weight: weight)
        case "mono": return .monospacedSystemFont(ofSize: s, weight: weight)
        case let f: return NSFont(name: ThemeFonts.name(f, base: baseURL), size: s) ?? .systemFont(ofSize: s, weight: weight)
        }
    }

    func cased(_ s: String) -> String {
        switch letterCase {
        case .uppercase: s.uppercased()
        case .lowercase: s.lowercased()
        default: s
        }
    }

    enum IconValue { case text(String), image(NSImage) }

    func icon(_ symbol: String) -> IconValue? {
        guard let v = skin?.icons?[symbol] else { return nil }
        if v.hasPrefix("image:"), let base = baseURL,
           let u = packageFile(base, String(v.dropFirst(6))), let i = NSImage(contentsOf: u) { return .image(i) }
        return .text(v)
    }

    func color(_ s: String?) -> Color? { s.flatMap(Color.init(hexString:)) }
}

/// Registers fonts that come with theme packages (for this process only) and remembers their PostScript names.
enum ThemeFonts {
    private static var names: [String: String] = [:]

    static func name(_ font: String, base: URL?) -> String {
        guard font.hasSuffix(".ttf") || font.hasSuffix(".otf"), let base, let url = packageFile(base, font) else { return font }
        if let n = names[url.path] { return n }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        let n = descriptors.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String } ?? font
        names[url.path] = n
        return n
    }
}

/// Theme sounds (off unless the user turns them on in the menu). Built-in sounds are synthesized, so themes need no files.
enum ThemeSound {
    static var isEnabled: Bool { Defaults.bool("themeSounds", false) }
    private static var cache: [String: NSSound] = [:]

    static func play(_ event: String, _ theme: Theme) {
        guard isEnabled, let name = theme.skin?.sounds?[event] else { return }
        let key = (theme.baseURL?.path ?? "") + "/" + name
        if cache[key] == nil {
            if let data = synthesized(name) { cache[key] = NSSound(data: data) }
            else if let base = theme.baseURL, let u = packageFile(base, name) { cache[key] = NSSound(contentsOf: u, byReference: true) }
        }
        guard let s = cache[key] else { return }
        s.stop()
        s.play()
    }

    /// 16-bit mono WAV data for the built-in sounds.
    private static func synthesized(_ name: String) -> Data? {
        let rate = 44100.0
        let samples: [Double]
        switch name {
        case "click":
            var seed: UInt32 = 7
            samples = (0..<Int(rate * 0.018)).map { i in
                seed = seed &* 1664525 &+ 1013904223
                return (Double(seed >> 16) / 32768 - 1) * exp(-Double(i) / (rate * 0.003)) * 0.5
            }
        case "blip":
            samples = (0..<Int(rate * 0.07)).map { i in
                let t = Double(i) / rate, f = t < 0.03 ? 880.0 : 1320.0
                return (sin(2 * .pi * f * t) >= 0 ? 0.18 : -0.18) * (1 - t / 0.07)
            }
        case "tick":
            samples = (0..<Int(rate * 0.01)).map { i in
                let t = Double(i) / rate
                return sin(2 * .pi * 2200 * t) * exp(-t / 0.002) * 0.45
            }
        default: return nil
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples.count * 2)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count * 2))
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        return d
    }
}

extension Font {
    /// A text size in the bar's current theme (its font, scale and weight).
    static func bar(_ size: CGFloat, _ weight: Font.Weight? = nil) -> Font { Theme.current.font(size, weight) }
}

/// An Apple symbol, or what the theme shows instead (text or the theme's own image).
struct Icon: View {
    let name: String
    @Environment(\.theme) private var theme
    init(_ name: String) { self.name = name }

    var body: some View {
        switch theme.icon(name) {
        case .text(let s): Text(s).lineLimit(1).fixedSize()
        case .image(let i): Image(nsImage: i).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(height: 16)
        case nil: Image(systemName: name)
        }
    }
}

// MARK: drawing

/// A button's background in a skinned theme.
struct SkinBackground: View {
    var role: Role? = nil
    var isPressed = false
    /// inside a shared group: drawn only while pressed or highlighted
    var isGroupItem = false
    @Environment(\.theme) private var theme

    var body: some View {
        let l = theme.layer(role, pressed: isPressed)
        if !isGroupItem || isPressed || role != nil {
            GeometryReader { g in
                let r = min(l.radius, g.size.height / 2)
                let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
                ZStack {
                    if let f = l.fill {
                        let paint = LinearGradient(colors: [f, l.fill2 ?? f], startPoint: .top, endPoint: .bottom)
                        if l.border == "pixel" { PixelShape(step: l.borderWidth).fill(paint) } else { shape.fill(paint) }
                    }
                    if !isGroupItem { SkinBorder(l: l, size: g.size) }
                }
                .shadow(color: .black.opacity(0.6 * l.shadow), radius: 2 * l.shadow, y: l.shadow)
                .shadow(color: l.glowColor.opacity(l.glow > 0 ? 0.9 : 0), radius: l.glow)
            }
        }
    }
}

/// The border styles: solid, dashed, pixel (notched corners, optional bevel), ascii (brackets), sketch (hand-drawn).
struct SkinBorder: View {
    let l: ResolvedLayer
    let size: CGSize
    @Environment(\.theme) private var theme

    var body: some View {
        let r = min(l.radius, size.height / 2), w = l.borderWidth
        switch l.border {
        case "solid": RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(l.borderColor, lineWidth: w)
        case "dashed": RoundedRectangle(cornerRadius: r, style: .continuous)
            .strokeBorder(l.borderColor, style: StrokeStyle(lineWidth: w, dash: [3 * w, 2 * w]))
        case "pixel": PixelBorder(color: l.borderColor, width: w, bevel: l.bevel)
        case "ascii": EmptyView() // drawn around the label by LiquidPress
        case "sketch":
            ZStack {
                SketchShape(seed: Int(size.width), radius: r).stroke(l.borderColor, lineWidth: w)
                SketchShape(seed: Int(size.width) + 7, radius: r).stroke(l.borderColor.opacity(0.5), lineWidth: w * 0.6)
            }
        default: EmptyView()
        }
    }
}

/// Pixel-art frame: four edges with the corners left out; a bevel lightens the top-left and darkens the bottom-right inside.
struct PixelBorder: View {
    let color: Color
    let width: CGFloat
    let bevel: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, p = width
            ZStack(alignment: .topLeading) {
                if bevel {
                    Rectangle().fill(.white.opacity(0.45)).frame(width: w - 2 * p, height: p).offset(x: p, y: p)
                    Rectangle().fill(.white.opacity(0.45)).frame(width: p, height: h - 2 * p).offset(x: p, y: p)
                    Rectangle().fill(.black.opacity(0.3)).frame(width: w - 2 * p, height: p).offset(x: p, y: h - 2 * p)
                    Rectangle().fill(.black.opacity(0.3)).frame(width: p, height: h - 2 * p).offset(x: w - 2 * p, y: p)
                }
                Rectangle().fill(color).frame(width: w - 2 * p, height: p).offset(x: p)
                Rectangle().fill(color).frame(width: w - 2 * p, height: p).offset(x: p, y: h - p)
                Rectangle().fill(color).frame(width: p, height: h - 2 * p).offset(y: p)
                Rectangle().fill(color).frame(width: p, height: h - 2 * p).offset(x: w - p, y: p)
            }
        }
    }
}

/// A rectangle with its corner pixels cut off, so a pixel frame's fill doesn't show in the notches.
struct PixelShape: Shape {
    let step: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: r.minX + step, y: r.minY, width: r.width - 2 * step, height: r.height))
        p.addRect(CGRect(x: r.minX, y: r.minY + step, width: r.width, height: r.height - 2 * step))
        return p
    }
}

/// A rounded rectangle with a slightly wobbly, hand-drawn outline (the same every time for the same seed).
struct SketchShape: Shape {
    let seed: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var s = UInt32(truncatingIfNeeded: seed &* 2654435761)
        func j() -> CGFloat { s = s &* 1664525 &+ 1013904223; return CGFloat(s >> 24) / 255 * 1.6 - 0.8 }
        let r = min(radius, rect.height / 2), b = rect.insetBy(dx: 1, dy: 1)
        var p = Path()
        p.move(to: CGPoint(x: b.minX + r + j(), y: b.minY + j()))
        p.addQuadCurve(to: CGPoint(x: b.maxX - r, y: b.minY + j()), control: CGPoint(x: b.midX, y: b.minY + j()))
        p.addQuadCurve(to: CGPoint(x: b.maxX + j(), y: b.minY + r), control: CGPoint(x: b.maxX, y: b.minY))
        p.addQuadCurve(to: CGPoint(x: b.maxX + j(), y: b.maxY - r), control: CGPoint(x: b.maxX + j(), y: b.midY))
        p.addQuadCurve(to: CGPoint(x: b.maxX - r, y: b.maxY + j()), control: CGPoint(x: b.maxX, y: b.maxY))
        p.addQuadCurve(to: CGPoint(x: b.minX + r, y: b.maxY + j()), control: CGPoint(x: b.midX, y: b.maxY + j()))
        p.addQuadCurve(to: CGPoint(x: b.minX + j(), y: b.maxY - r), control: CGPoint(x: b.minX, y: b.maxY))
        p.addQuadCurve(to: CGPoint(x: b.minX + j(), y: b.minY + r), control: CGPoint(x: b.minX + j(), y: b.midY))
        p.addQuadCurve(to: CGPoint(x: b.minX + r + 2, y: b.minY + j()), control: CGPoint(x: b.minX, y: b.minY))
        return p
    }
}

/// The bar behind the buttons in a skinned theme: color or gradient and a pattern.
struct SkinBarBackground: View {
    let style: BarStyle
    let theme: Theme

    var body: some View {
        let a = theme.color(style.fill) ?? .black
        ZStack {
            LinearGradient(colors: [a, theme.color(style.fill2) ?? a], startPoint: .leading, endPoint: .trailing)
            let c = theme.color(style.patternColor) ?? .white.opacity(0.5)
            switch style.pattern {
            case "stars":
                Canvas { ctx, size in
                    var s: UInt32 = 42
                    for _ in 0..<Int(size.width / 9) {
                        s = s &* 1664525 &+ 1013904223; let x = CGFloat(s >> 8 & 0xFFFF) / 65535 * size.width
                        s = s &* 1664525 &+ 1013904223; let y = CGFloat(s >> 8 & 0xFFFF) / 65535 * size.height
                        ctx.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: 1, height: 1)), with: .color(c))
                    }
                }
            case "grid":
                Canvas { ctx, size in
                    var p = Path()
                    stride(from: 0, through: size.width, by: 8).forEach { p.addRect(CGRect(x: $0, y: 0, width: 0.5, height: size.height)) }
                    stride(from: 0, through: size.height, by: 8).forEach { p.addRect(CGRect(x: 0, y: $0, width: size.width, height: 0.5)) }
                    ctx.fill(p, with: .color(c))
                }
            default: EmptyView()
            }
        }
    }
}

/// Drawn over the whole bar: CRT scanlines.
struct SkinBarOverlay: View {
    let style: BarStyle

    var body: some View {
        if style.overlay == "scanlines" {
            Canvas { ctx, size in
                var p = Path()
                stride(from: 2, through: size.height, by: 3).forEach { p.addRect(CGRect(x: 0, y: $0, width: size.width, height: 1)) }
                ctx.fill(p, with: .color(.black.opacity(0.4)))
            }
            .allowsHitTesting(false)
        }
    }
}

/// Press effects that move the button: a short shake, a tilt.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 2.5 * sin(amount * .pi * 6), y: 0))
    }
}
