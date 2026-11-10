import SwiftUI

// Liquid Glass pieces: glass capsule background, liquid press behavior, button group, slider with a lens knob.
extension Color {
    init(hex: UInt32, _ o: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: o)
    }
}

enum Metrics {
    static let barHeight: CGFloat = 30
    static let buttonHeight: CGFloat = 26
    static let spacing: CGFloat = 4
    static let iconWidth: CGFloat = 40
    static let narrowWidth: CGFloat = 32
    static let escWidth: CGFloat = 64
}

enum Springs {
    /// on press: fast, slight overshoot
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.58)
    /// on release: springs back with a wobble
    static let release = Animation.spring(response: 0.48, dampingFraction: 0.42)
    /// springs with less overshoot for the minimal theme
    static let minimalPress = Animation.spring(response: 0.24, dampingFraction: 0.66)
    static let minimalRelease = Animation.spring(response: 0.5, dampingFraction: 0.58)

    static func press(_ t: Theme) -> Animation { t.isMinimal ? minimalPress : press }
    static func release(_ t: Theme) -> Animation { t.isMinimal ? minimalRelease : release }
    /// while following the finger
    static let follow = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.7)
}

/// Live state of a touch on a button (a class because SwiftUI's @State is a macro this toolchain can't expand).
final class PressState: ObservableObject {
    @Published var isPressed = false
    @Published var position: CGPoint = .zero
    @Published var dragOffset: CGSize = .zero
    @Published var ripple: CGFloat = 1
    @Published var glow: Double = 0
    /// counts presses for the shake effect
    @Published var shakes: CGFloat = 0
    var size: CGSize = .zero
    var frameInBar: CGRect = .zero
    /// press-and-slide in progress
    var isSliding = false
}

/// The ambient light behind the glass lights up where touched, too.
final class TouchLight: ObservableObject {
    static let shared = TouchLight()
    @Published var position: CGPoint = .zero
    @Published var intensity: Double = 0
}

/// Glass background. When `b` is given it reacts to touch: light under the finger, a spreading ring, a glowing edge.
struct GlassBackground: View {
    var role: Role? = nil
    @ObservedObject var b: PressState = PressState()
    @Environment(\.theme) private var theme

    private var highlight: Color? { role.flatMap(theme.glassColor) }

    var body: some View {
        if theme.isSkin { SkinBackground(role: role, isPressed: b.isPressed) } else { glass }
    }

    private var glass: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), h = max(1, g.size.height)
            let center = UnitPoint(x: b.position.x / w, y: b.position.y / h)
            if theme.isMinimal { minimal(center, theme.shape(h)) } else { classic(w: w, center: center, theme.shape(h)) }
        }
    }

    /// Minimal Liquid Glass: clear in the middle, glass thickening toward the edge; bright at the top edge, reflected light at the bottom.
    private func minimal(_ center: UnitPoint, _ shape: RoundedRectangle) -> some View {
        let p = b.glow, t = theme, tint = theme.glassTint
        return ZStack {
            shape.fill(EllipticalGradient(stops: [.init(color: tint.opacity((0.07 - 0.03 * p) * t.glass), location: 0.55),
                                                  .init(color: tint.opacity((0.16 + 0.06 * p) * t.glass), location: 1)]))
            if let highlight {
                shape.fill(EllipticalGradient(stops: [.init(color: highlight.opacity(0.82), location: 0.55),
                                                      .init(color: highlight.opacity(0.95), location: 1)]))
            }
            // glass thickness
            shape.strokeBorder(tint.opacity((0.06 + 0.1 * p) * t.edge), lineWidth: 2).blur(radius: 1.5).clipShape(shape)
            // light spreading from under the finger
            shape
                .fill(RadialGradient(colors: [tint.opacity(0.32 * p * t.glow), tint.opacity(0.08 * p * t.glow), .clear],
                                     center: center, startRadius: 0, endRadius: 30))
                .blendMode(.plusLighter)
            // refracting edge
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity((0.55 + 0.35 * p) * t.edge), location: 0),
                                                      .init(color: tint.opacity((0.10 + 0.15 * p) * t.edge), location: 0.38),
                                                      .init(color: tint.opacity((0.06 + 0.12 * p) * t.edge), location: 0.62),
                                                      .init(color: tint.opacity((0.30 + 0.3 * p) * t.edge), location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.6 * t.shadow), radius: 1.5, y: 0.5)
    }

    private func classic(w: CGFloat, center: UnitPoint, _ shape: RoundedRectangle) -> some View {
        let t = theme, tint = theme.glassTint
        return ZStack {
                shape.fill(LinearGradient(colors: [tint.opacity((b.isPressed ? 0.26 : 0.18) * t.glass), tint.opacity((b.isPressed ? 0.1 : 0.05) * t.glass),
                                                   tint.opacity((b.isPressed ? 0.16 : 0.10) * t.glass)],
                                          startPoint: .top, endPoint: .bottom))
                if let highlight {
                    shape.fill(LinearGradient(colors: [highlight.opacity(0.85), highlight.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                }
                // highlight on the top edge
                shape
                    .fill(LinearGradient(colors: [.white.opacity(0.28 * t.edge), .clear], startPoint: .top, endPoint: .center))
                    .padding(.horizontal, 4).padding(.top, 0.8).padding(.bottom, 11)
                // light under the finger
                shape
                    .fill(RadialGradient(colors: [tint.opacity(0.75 * b.glow * t.glow), tint.opacity(0.18 * b.glow * t.glow), .clear],
                                         center: center, startRadius: 0, endRadius: 14 + 26 * b.glow))
                    .blendMode(.plusLighter)
                // ring of light spreading on touch
                Circle()
                    .strokeBorder(tint.opacity(0.7 * (1 - b.ripple) * t.glow), lineWidth: 2.5)
                    .blur(radius: 1.5)
                    .frame(width: 8 + w * 1.6 * b.ripple, height: 8 + w * 1.6 * b.ripple)
                    .position(b.position)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
                // edge: catches the light while pressed
                shape.strokeBorder(LinearGradient(colors: [.white.opacity((0.42 + 0.45 * b.glow) * t.edge), tint.opacity((0.08 + 0.3 * b.glow) * t.edge),
                                                           tint.opacity((0.2 + 0.4 * b.glow) * t.edge)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.7 + 0.4 * b.glow)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.55 * t.shadow), radius: 2.5, y: 1)
            .shadow(color: tint.opacity(0.35 * b.glow * t.glow), radius: 6)
    }
}

/// Liquid glass press: on touch the button grows and glows and follows the finger elastically;
/// on release it springs and wobbles back into place; the action runs if the finger lifts over the button.
struct LiquidPress: ViewModifier {
    enum Kind { case capsule, bubble }
    var kind: Kind = .capsule
    var role: Role? = nil
    /// item in a scrolling strip: doesn't stretch, and the action doesn't run if the finger slides
    var isScrollable = false
    /// called with the horizontal offset when pressing and sliding sideways (like brightness/volume)
    var onSlide: ((CGFloat) -> Void)? = nil
    var onSlideEnd: (() -> Void)? = nil
    /// position in the group: the first/last item's highlight follows the capsule's rounded end
    var isLeadingEnd = false
    var isTrailingEnd = false
    let action: () -> Void
    @StateObject private var b = PressState()
    @Environment(\.theme) private var theme
    @Environment(\.studioInspecting) private var isInspecting

    private var studioTarget: StudioTarget {
        if let k = role?.key { return .role(k) }
        return kind == .bubble ? .group : .button
    }

    func body(content: Content) -> some View {
        let tx = b.dragOffset.width, ty = b.dragOffset.height
        let stretch = abs(tanh(tx / 60))
        let minimal = theme.isMinimal, effect = theme.pressEffect
        let k = CGFloat(theme.bounce) * (effect == .liquid ? 1 : 0)
        let pop: CGFloat = effect == .pop && b.isPressed ? (kind == .capsule ? 0.12 : 0.08) : 0
        bracketed(content)
            .font(theme.font(13))
            .textCase(theme.letterCase)
            .tracking(theme.tracking)
            .foregroundStyle(theme.isSkin ? theme.layer(role, pressed: b.isPressed).text : theme.text)
            .frame(maxHeight: .infinity)
            .background {
                switch kind {
                case .capsule:
                    GlassBackground(role: role, b: b)
                case .bubble where theme.isSkin:
                    SkinBackground(role: role, isPressed: b.isPressed, isGroupItem: true)
                case .bubble:
                    ZStack {
                        if let highlight = role.flatMap(theme.glassColor) {
                            let r = theme.radius(Metrics.buttonHeight)
                            UnevenRoundedRectangle(topLeadingRadius: isLeadingEnd ? r : 0, bottomLeadingRadius: isLeadingEnd ? r : 0,
                                                   bottomTrailingRadius: isTrailingEnd ? r : 0, topTrailingRadius: isTrailingEnd ? r : 0)
                                .fill(highlight.opacity(0.7))
                        }
                        // a glass drop bulging out of the group
                        GlassBackground(b: b)
                            .padding(.horizontal, minimal ? -2 : -3).padding(.vertical, -1)
                            .scaleEffect(b.isPressed ? 1 : (minimal ? 0.82 : 0.6))
                            .opacity(b.isPressed ? 1 : 0)
                    }
                }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear {
                        b.size = g.size
                        b.frameInBar = g.frame(in: .named("bar"))
                        // screenshot testing: -testPressed YES → buttons look pressed
                        if UserDefaults.standard.bool(forKey: "testPressed") {
                            b.isPressed = true; b.glow = 1; b.ripple = 0.45
                            b.position = CGPoint(x: g.size.width * 0.35, y: g.size.height * 0.4)
                        }
                    }
                    .onChange(of: g.frame(in: .named("bar"))) { _, c in b.size = c.size; b.frameInBar = c }
            })
            .background { if isInspecting { StudioHitReporter(target: studioTarget) } }
            .contentShape(Rectangle())
            .scaleEffect(b.isPressed ? 1 + pop + k * (kind == .capsule ? (minimal ? 0.08 : 0.1) : (minimal ? 0.05 : 0.04)) : 1)
            .scaleEffect(x: 1 + k * (minimal ? 0.06 : 0.12) * stretch, y: 1 - k * (minimal ? 0.035 : 0.07) * stretch)
            .offset(x: k * (minimal ? 4 : 7) * tanh(tx / 45), y: k * (minimal ? 1 : 2) * tanh(ty / 25))
            .modifier(ShakeEffect(amount: b.shakes))
            .rotationEffect(.degrees(effect == .wobble && b.isPressed ? -4 : 0))
            .animation(Springs.follow, value: b.dragOffset)
            .animation(b.isPressed ? Springs.press(theme) : Springs.release(theme), value: b.isPressed)
            .zIndex(b.isPressed ? 1 : 0)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    if !b.isPressed {
                        b.isPressed = true
                        b.ripple = 0
                        withAnimation(.easeOut(duration: 0.6)) { b.ripple = 1 }
                        withAnimation(.easeOut(duration: 0.12)) { b.glow = 1 }
                        if effect == .shake { withAnimation(.linear(duration: 0.3)) { b.shakes += 1 } }
                        ThemeSound.play("tap", theme)
                        TouchLight.shared.position = CGPoint(x: b.frameInBar.minX + e.location.x, y: b.frameInBar.midY)
                        withAnimation(.easeOut(duration: 0.18)) { TouchLight.shared.intensity = 1 }
                    }
                    b.position = e.location
                    if let onSlide, b.isSliding || abs(e.translation.width) > 6 {
                        b.isSliding = true
                        b.dragOffset = .zero
                        onSlide(e.translation.width)
                    } else if !isScrollable {
                        b.dragOffset = e.translation
                    }
                    withAnimation(Springs.follow) { TouchLight.shared.position.x = b.frameInBar.minX + e.location.x }
                }
                .onEnded { e in
                    var isInside = CGRect(origin: .zero, size: b.size).insetBy(dx: -14, dy: -24).contains(e.location)
                    if isScrollable && abs(e.translation.width) > 8 { isInside = false }
                    if b.isSliding { b.isSliding = false; onSlideEnd?(); isInside = false }
                    b.isPressed = false
                    b.dragOffset = .zero
                    withAnimation(.easeOut(duration: 0.55)) { b.glow = 0 }
                    withAnimation(.easeOut(duration: 0.7)) { TouchLight.shared.intensity = 0 }
                    if isInside { action() }
                })
    }
}

/// The shared background of a button group: glass, or the skin's group layer.
struct GroupBackground: View {
    var role: Role? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        if theme.isSkin {
            let l = theme.groupLayer(role)
            GeometryReader { g in
                let shape = RoundedRectangle(cornerRadius: min(l.radius, g.size.height / 2), style: .continuous)
                ZStack {
                    if let f = l.fill { shape.fill(LinearGradient(colors: [f, l.fill2 ?? f], startPoint: .top, endPoint: .bottom)) }
                    SkinBorder(l: l, size: g.size)
                }
                .shadow(color: l.glowColor.opacity(l.glow > 0 ? 0.9 : 0), radius: l.glow)
            }
        } else {
            GlassBackground(role: role).clipShape(theme.shape(Metrics.buttonHeight))
        }
    }
}

extension LiquidPress {
    /// ASCII borders hug the label: "[esc]", "[ / ]".
    @ViewBuilder func bracketed(_ c: Content) -> some View {
        let l = theme.layer(role, pressed: b.isPressed)
        if theme.isSkin && l.border == "ascii" {
            // the brackets never give up width: in a tight group the Touch Bar otherwise cuts "]" down to a sliver
            HStack(spacing: 2) { Text(l.opening).fixedSize().layoutPriority(1); c; Text(l.closing).fixedSize().layoutPriority(1) }
                .padding(.horizontal, 3)
        } else {
            c
        }
    }
}

/// Single-line button text. On the Touch Bar, Text doesn't fit the width it measures itself and truncates ("Tod…");
/// the width is measured with AppKit and given with a little slack.
struct BarText: View {
    let text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .medium
    @Environment(\.theme) private var theme
    init(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) {
        self.text = L(text); self.size = size; self.weight = weight
    }
    init(verbatim text: String, size: CGFloat = 13) { self.text = text; self.size = size }
    /// equal-width digits, for values that change (percentages, sizes)
    var tabular = false
    init(verbatim text: String, tabular: Bool) { self.text = text; self.tabular = tabular }
    var body: some View {
        // Text clips a changing value to a width it gets wrong by a point or two; thin spaces give it room
        let s = tabular ? "\u{2009}" + theme.cased(text) + "\u{2009}" : theme.cased(text)
        let measured = tabular ? String(s.map { $0.isNumber ? "0" : $0 }) : s
        let w = (measured as NSString).size(withAttributes: [.font: theme.nsFont(size, weight), .kern: theme.tracking]).width
        let f = theme.font(size, Font.Weight(weight))
        // measured with zeros so the width doesn't jump as a value changes
        Text(s).font(f).tracking(theme.tracking).lineLimit(1).frame(width: ceil(w) + 6)
    }
}

extension Font.Weight {
    init(_ w: NSFont.Weight) {
        switch w {
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .regular: self = .regular
        default: self = .medium
        }
    }
}

struct GlassButton<Label: View>: View {
    var width: CGFloat? = Metrics.iconWidth
    var highlight: Role? = nil
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    var isScrollable = false
    var onSlide: ((CGFloat) -> Void)? = nil
    var onSlideEnd: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        // skins may show text instead of symbols, so a fixed width becomes a minimum
        label()
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: theme.isSkin ? nil : width)
            .frame(minWidth: theme.isSkin ? width : nil)
            .frame(height: Metrics.buttonHeight)
            .modifier(LiquidPress(role: highlight, isScrollable: isScrollable, onSlide: onSlide, onSlideEnd: onSlideEnd, action: action))
            .frame(height: Metrics.buttonHeight)
    }

    /// Press and slide changes the value (the original brightness/volume behavior).
    func whenSliding(_ k: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) -> GlassButton {
        var t = self
        t.onSlide = k
        t.onSlideEnd = onEnd
        return t
    }

    /// Sits in a scrolling strip; doesn't count as pressed if the finger slides.
    func inScrollingStrip() -> GlassButton {
        var t = self
        t.isScrollable = true
        return t
    }
}

extension GlassButton where Label == Icon {
    init(_ symbol: String, width: CGFloat? = Metrics.iconWidth, highlight: Role? = nil, action: @escaping () -> Void) {
        self.width = width
        self.highlight = highlight
        self.action = action
        self.label = { Icon(symbol) }
    }
}

struct GroupButton: Identifiable {
    let id = UUID()
    var symbol: String? = nil
    var text: String? = nil
    var dot: Color? = nil
    var highlight: Role? = nil
    /// shown as written, not translated (labels from layouts)
    var isVerbatim = false
    let action: () -> Void
}

struct ButtonGroup: View {
    let buttons: [GroupButton]
    var buttonWidth: CGFloat? = nil
    /// when given, the group's glass is tinted this color (typing suggestions are dark blue-gray in the original)
    var backgroundTint: Role? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.splitsGroups ? Metrics.spacing : 0) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { i, t in
                if i > 0 && !theme.splitsGroups { Rectangle().fill(theme.layer(nil).text.opacity(0.13)).frame(width: 0.6).padding(.vertical, 5) }
                Group {
                    if let n = t.dot {
                        Circle().fill(n).frame(width: 13, height: 13)
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                                  startPoint: .top, endPoint: .center)))
                    } else if let s = t.symbol { Icon(s) } else { Text(t.isVerbatim ? t.text ?? "" : L(t.text ?? "")).lineLimit(1) }
                }
                .frame(maxWidth: buttonWidth == nil ? .infinity : nil)
                // like GlassButton: in a skin the width is a minimum (text labels, ASCII brackets)
                .frame(width: theme.isSkin ? nil : buttonWidth)
                .frame(minWidth: theme.isSkin ? buttonWidth : nil)
                .modifier(LiquidPress(kind: theme.splitsGroups ? .capsule : .bubble, role: t.highlight, isLeadingEnd: i == 0, isTrailingEnd: i == buttons.count - 1, action: t.action))
            }
        }
        .frame(height: Metrics.buttonHeight)
        .background { if !theme.splitsGroups { GroupBackground(role: backgroundTint) } }
    }
}

/// Slider whose knob turns into a clear glass lens while dragged, like in iOS 26.
struct GlassSlider: View {
    @Binding var value: Float
    var isThin = false
    /// when given, the filled part uses this color (the blue of the original brightness/volume slider)
    var fillColor: Color? = nil
    var onValueChange: (Float) -> Void = { _ in }
    @StateObject private var b = PressState()
    @Environment(\.theme) private var theme
    @Environment(\.studioInspecting) private var isInspecting

    // One gesture on a container that outlives the three looks: switching between a glass and a skinned theme
    // mid-drag replaces the look, and a gesture attached to it would end without onEnded (the knob stays a lens).
    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width)
            ZStack {
                if theme.isSkin { skinned(w) } else if theme.isMinimal { minimal(w) } else { classic(w) }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(w))
        }
        .frame(height: Metrics.buttonHeight)
        .background { if isInspecting { StudioHitReporter(target: .slider) } }
    }

    /// Skinned theme: a track in the theme's colors and a knob drawn like its buttons; with ASCII borders, [====|----].
    @ViewBuilder private func skinned(_ w: CGFloat) -> some View {
        let v = CGFloat(value)
        // the track keeps its normal look while held (a pressed look such as inverted colors would hide it)
        let l = theme.layer(nil)
        let fill = theme.sliderFill ?? theme.layer(.primary).fill ?? l.borderColor
        Group {
            if l.border == "ascii" {
                let font = theme.nsFont(13, .medium)
                let charWidth = max(1, ("=" as NSString).size(withAttributes: [.font: font]).width)
                let count = max(4, Int(w / charWidth) - 3), filled = Int((v * CGFloat(count)).rounded())
                Text(l.opening + String(repeating: "=", count: filled) + "|" + String(repeating: "-", count: max(0, count - filled)) + l.closing)
                    .font(theme.font(13)).foregroundStyle(l.text).lineLimit(1).fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let knob = CGSize(width: isThin ? 12 : 26, height: isThin ? 12 : 20)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: min(l.radius, 3)).fill(l.borderColor.opacity(0.3)).frame(height: isThin ? 4 : 6)
                    RoundedRectangle(cornerRadius: min(l.radius, 3)).fill(fill).frame(width: max(6, w * v), height: isThin ? 4 : 6)
                    SkinBackground(isPressed: b.isPressed)
                        .frame(width: knob.width, height: knob.height)
                        .scaleEffect(b.isPressed ? 1.15 : 1)
                        .offset(x: min(max(0, w * v - knob.width / 2), w - knob.width))
                        .animation(Springs.minimalPress, value: b.isPressed)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// Minimal theme: a white capsule knob at rest; while dragging it becomes a clear lens magnifying the track below.
    @ViewBuilder private func minimal(_ w: CGFloat) -> some View {
        let v = CGFloat(value)
        let knob: CGSize = isThin ? .init(width: 12, height: 12) : .init(width: 30, height: 20)
        let ray: CGFloat = 4
        let isLens = b.isPressed
        let x = min(max(0, w * v - knob.width / 2), w - knob.width)
        let color = theme.sliderFill ?? fillColor ?? .white
        let trackView = ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.18)).frame(height: ray)
            Capsule().fill(color).frame(width: max(ray, w * v), height: ray)
        }
        ZStack(alignment: .leading) {
            trackView
            ZStack {
                Capsule().fill(isLens ? Color.white.opacity(0.06) : Color(hex: 0xF2F2F7))
                if isLens {
                    // lens: the track under the knob looks 30% larger
                    trackView
                        .frame(width: w, height: knob.height)
                        .scaleEffect(1.3, anchor: UnitPoint(x: (x + knob.width / 2) / w, y: 0.5))
                        .offset(x: -x)
                        .frame(width: knob.width, height: knob.height, alignment: .leading)
                        .clipShape(Capsule())
                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 2).blur(radius: 1.5).clipShape(Capsule())
                    Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                                                  .init(color: .white.opacity(0.25), location: 0.4),
                                                                  .init(color: .white.opacity(0.4), location: 1)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                }
            }
            .frame(width: knob.width, height: knob.height)
            .shadow(color: .black.opacity(isLens ? 0.4 : 0.55), radius: isLens ? 1.5 : 1, y: 0.5)
            .scaleEffect(x: isLens ? 1.32 : 1, y: isLens ? 1.22 : 1)
            .offset(x: x)
            .animation(isLens ? Springs.minimalPress : Springs.minimalRelease, value: isLens)
        }
        .frame(maxHeight: .infinity)
    }

    private func dragGesture(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { e in
                if !b.isPressed { b.isPressed = true }
                withAnimation(Springs.follow) { value = Float(min(1, max(0, e.location.x / max(1, w)))) }
                onValueChange(value)
            }
            .onEnded { _ in b.isPressed = false }
    }

    @ViewBuilder private func classic(_ w: CGFloat) -> some View {
        let v = CGFloat(value)
        let knob: CGSize = isThin ? .init(width: 12, height: 12) : .init(width: 34, height: 22)
        let ray: CGFloat = isThin ? 4 : 6
        let isLens = b.isPressed
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.13)).frame(height: ray)
                .overlay(Capsule().stroke(.black.opacity(0.5), lineWidth: 0.5))
            Capsule().fill(LinearGradient(colors: (theme.sliderFill ?? fillColor).map { [$0.opacity(0.8), $0] } ?? [.white.opacity(0.55), .white],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: max(ray, w * v), height: ray)
            ZStack {
                Capsule().fill(LinearGradient(colors: [.white.opacity(isLens ? 0.12 : 0.55), .white.opacity(isLens ? 0.03 : 0.2)],
                                              startPoint: .top, endPoint: .bottom))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(isLens ? 0.5 : 0.2), .clear], startPoint: .top, endPoint: .center))
                    .padding(.horizontal, 3).padding(.top, 0.8).padding(.bottom, knob.height * 0.45)
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(isLens ? 0.25 : 0.5), .white.opacity(0.7)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: isLens ? 1.1 : 0.7)
            }
            .frame(width: knob.width, height: knob.height)
            .shadow(color: .black.opacity(isLens ? 0.35 : 0.6), radius: 3, y: 1)
            .shadow(color: .white.opacity(isLens ? 0.35 : 0), radius: 6)
            .scaleEffect(x: isLens ? 1.3 : 1, y: isLens ? 1.18 : 1)
            .offset(x: min(max(0, w * v - knob.width / 2), w - knob.width))
            .animation(isLens ? Springs.press : Springs.release, value: isLens)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Grow-and-sharpen when panels change.
struct FocusIn: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content.scaleEffect(0.92 + 0.08 * p).blur(radius: (1 - p) * 2.5).opacity(p)
    }
}

extension AnyTransition {
    static var focusIn: AnyTransition { .modifier(active: FocusIn(p: 0), identity: FocusIn(p: 1)) }
}
