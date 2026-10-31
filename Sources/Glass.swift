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

/// Appearance theme ("Theme" in the menu). Classic: pronounced glass, bright highlight, light ring.
/// Minimal: Liquid Glass close to macOS 26; light refracting at the edge, glass thickening toward the edge, no ring. Ambient light is a separate option.
enum Theme: String, CaseIterable {
    case classic = "klasik", minimal = "sade"

    var name: String { L(baseName) }

    private var baseName: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal Liquid Glass"
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.classic
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Springs {
    /// on press: fast, slight overshoot
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.58)
    /// on release: springs back with a wobble
    static let release = Animation.spring(response: 0.48, dampingFraction: 0.42)
    /// springs with less overshoot for the minimal theme
    static let minimalPress = Animation.spring(response: 0.24, dampingFraction: 0.66)
    static let minimalRelease = Animation.spring(response: 0.5, dampingFraction: 0.58)

    static func press(_ t: Theme) -> Animation { t == .minimal ? minimalPress : press }
    static func release(_ t: Theme) -> Animation { t == .minimal ? minimalRelease : release }
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
    var highlight: Color? = nil
    @ObservedObject var b: PressState = PressState()
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), h = max(1, g.size.height)
            let center = UnitPoint(x: b.position.x / w, y: b.position.y / h)
            if theme == .minimal { minimal(center) } else { classic(w: w, center: center) }
        }
    }

    /// Minimal Liquid Glass: clear in the middle, glass thickening toward the edge; bright at the top edge, reflected light at the bottom.
    private func minimal(_ center: UnitPoint) -> some View {
        let p = b.glow
        return ZStack {
            Capsule().fill(EllipticalGradient(stops: [.init(color: .white.opacity(0.07 - 0.03 * p), location: 0.55),
                                                      .init(color: .white.opacity(0.16 + 0.06 * p), location: 1)]))
            if let highlight {
                Capsule().fill(EllipticalGradient(stops: [.init(color: highlight.opacity(0.82), location: 0.55),
                                                          .init(color: highlight.opacity(0.95), location: 1)]))
            }
            // glass thickness
            Capsule().strokeBorder(.white.opacity(0.06 + 0.1 * p), lineWidth: 2).blur(radius: 1.5).clipShape(Capsule())
            // light spreading from under the finger
            Capsule()
                .fill(RadialGradient(colors: [.white.opacity(0.32 * p), .white.opacity(0.08 * p), .clear],
                                     center: center, startRadius: 0, endRadius: 30))
                .blendMode(.plusLighter)
            // refracting edge
            Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.55 + 0.35 * p), location: 0),
                                                          .init(color: .white.opacity(0.10 + 0.15 * p), location: 0.38),
                                                          .init(color: .white.opacity(0.06 + 0.12 * p), location: 0.62),
                                                          .init(color: .white.opacity(0.30 + 0.3 * p), location: 1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
    }

    private func classic(w: CGFloat, center: UnitPoint) -> some View {
            ZStack {
                Capsule().fill(LinearGradient(colors: [.white.opacity(b.isPressed ? 0.26 : 0.18), .white.opacity(b.isPressed ? 0.1 : 0.05),
                                                       .white.opacity(b.isPressed ? 0.16 : 0.10)],
                                              startPoint: .top, endPoint: .bottom))
                if let highlight {
                    Capsule().fill(LinearGradient(colors: [highlight.opacity(0.85), highlight.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                }
                // highlight on the top edge
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    .padding(.horizontal, 4).padding(.top, 0.8).padding(.bottom, 11)
                // light under the finger
                Capsule()
                    .fill(RadialGradient(colors: [.white.opacity(0.75 * b.glow), .white.opacity(0.18 * b.glow), .clear],
                                         center: center, startRadius: 0, endRadius: 14 + 26 * b.glow))
                    .blendMode(.plusLighter)
                // ring of light spreading on touch
                Circle()
                    .strokeBorder(.white.opacity(0.7 * (1 - b.ripple)), lineWidth: 2.5)
                    .blur(radius: 1.5)
                    .frame(width: 8 + w * 1.6 * b.ripple, height: 8 + w * 1.6 * b.ripple)
                    .position(b.position)
                    .blendMode(.plusLighter)
                    .clipShape(Capsule())
                // edge: catches the light while pressed
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.42 + 0.45 * b.glow), .white.opacity(0.08 + 0.3 * b.glow),
                                                               .white.opacity(0.2 + 0.4 * b.glow)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.7 + 0.4 * b.glow)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
            .shadow(color: .white.opacity(0.35 * b.glow), radius: 6)
    }
}

/// Liquid glass press: on touch the button grows and glows and follows the finger elastically;
/// on release it springs and wobbles back into place; the action runs if the finger lifts over the button.
struct LiquidPress: ViewModifier {
    enum Kind { case capsule, bubble }
    var kind: Kind = .capsule
    var highlight: Color? = nil
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

    func body(content: Content) -> some View {
        let tx = b.dragOffset.width, ty = b.dragOffset.height
        let stretch = abs(tanh(tx / 60))
        let minimal = theme == .minimal
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            .background {
                switch kind {
                case .capsule:
                    GlassBackground(highlight: highlight, b: b)
                case .bubble:
                    ZStack {
                        if let highlight {
                            let r = Metrics.buttonHeight / 2
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
                        // screenshot testing: -tb2basili YES → buttons look pressed
                        if UserDefaults.standard.bool(forKey: "tb2basili") {
                            b.isPressed = true; b.glow = 1; b.ripple = 0.45
                            b.position = CGPoint(x: g.size.width * 0.35, y: g.size.height * 0.4)
                        }
                    }
                    .onChange(of: g.frame(in: .named("bar"))) { _, c in b.size = c.size; b.frameInBar = c }
            })
            .contentShape(Rectangle())
            .scaleEffect(b.isPressed ? (kind == .capsule ? (minimal ? 1.08 : 1.1) : (minimal ? 1.05 : 1.04)) : 1)
            .scaleEffect(x: 1 + (minimal ? 0.06 : 0.12) * stretch, y: 1 - (minimal ? 0.035 : 0.07) * stretch)
            .offset(x: (minimal ? 4 : 7) * tanh(tx / 45), y: (minimal ? 1 : 2) * tanh(ty / 25))
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

/// Single-line button text. On the Touch Bar, Text doesn't fit the width it measures itself and truncates ("Tod…");
/// the width is measured with AppKit and given with a little slack.
struct BarText: View {
    let text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .medium
    init(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) {
        self.text = L(text); self.size = size; self.weight = weight
    }
    var body: some View {
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        Text(text).font(.system(size: size, weight: Font.Weight(weight))).lineLimit(1).frame(width: ceil(w) + 6)
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
    var highlight: Color? = nil
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    var isScrollable = false
    var onSlide: ((CGFloat) -> Void)? = nil
    var onSlideEnd: (() -> Void)? = nil

    var body: some View {
        label()
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width)
            .frame(height: Metrics.buttonHeight)
            .modifier(LiquidPress(highlight: highlight, isScrollable: isScrollable, onSlide: onSlide, onSlideEnd: onSlideEnd, action: action))
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

extension GlassButton where Label == Image {
    init(_ symbol: String, width: CGFloat? = Metrics.iconWidth, highlight: Color? = nil, action: @escaping () -> Void) {
        self.width = width
        self.highlight = highlight
        self.action = action
        self.label = { Image(systemName: symbol) }
    }
}

struct GroupButton: Identifiable {
    let id = UUID()
    var symbol: String? = nil
    var text: String? = nil
    var dot: Color? = nil
    var highlight: Color? = nil
    let action: () -> Void
}

struct ButtonGroup: View {
    let buttons: [GroupButton]
    var buttonWidth: CGFloat? = nil
    /// when given, the group's glass is tinted this color (typing suggestions are dark blue-gray in the original)
    var backgroundTint: Color? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { i, t in
                if i > 0 { Rectangle().fill(.white.opacity(0.13)).frame(width: 0.6).padding(.vertical, 5) }
                Group {
                    if let n = t.dot {
                        Circle().fill(n).frame(width: 13, height: 13)
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                                  startPoint: .top, endPoint: .center)))
                    } else if let s = t.symbol { Image(systemName: s) } else { Text(L(t.text ?? "")).lineLimit(1) }
                }
                .frame(maxWidth: buttonWidth == nil ? .infinity : nil)
                .frame(width: buttonWidth)
                .modifier(LiquidPress(kind: .bubble, highlight: t.highlight, isLeadingEnd: i == 0, isTrailingEnd: i == buttons.count - 1, action: t.action))
            }
        }
        .frame(height: Metrics.buttonHeight)
        .background(GlassBackground(highlight: backgroundTint).clipShape(Capsule()))
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

    var body: some View {
        if theme == .minimal { minimal } else { classic }
    }

    /// Minimal theme: a white capsule knob at rest; while dragging it becomes a clear lens magnifying the track below.
    private var minimal: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), v = CGFloat(value)
            let knob: CGSize = isThin ? .init(width: 12, height: 12) : .init(width: 30, height: 20)
            let ray: CGFloat = 4
            let isLens = b.isPressed
            let x = min(max(0, w * v - knob.width / 2), w - knob.width)
            let color = fillColor ?? .white
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
            .contentShape(Rectangle())
            .gesture(dragGesture(w))
        }
        .frame(height: Metrics.buttonHeight)
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

    private var classic: some View {
        GeometryReader { g in
            let w = g.size.width, v = CGFloat(value)
            let knob: CGSize = isThin ? .init(width: 12, height: 12) : .init(width: 34, height: 22)
            let ray: CGFloat = isThin ? 4 : 6
            let isLens = b.isPressed
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13)).frame(height: ray)
                    .overlay(Capsule().stroke(.black.opacity(0.5), lineWidth: 0.5))
                Capsule().fill(LinearGradient(colors: fillColor.map { [$0.opacity(0.8), $0] } ?? [.white.opacity(0.55), .white],
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
            .contentShape(Rectangle())
            .gesture(dragGesture(w))
        }
        .frame(height: Metrics.buttonHeight)
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
