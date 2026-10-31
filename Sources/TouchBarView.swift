import SwiftUI

// The bar's layout matches the original: esc | app area | Control Strip.
struct TouchBarView: View {
    @ObservedObject var d: AppState

    var body: some View {
        // while the brightness/volume slider is open the rest of the bar dims (like the original);
        // while pressing and sliding the button stays in the hierarchy so the finger's movement isn't cut off
        let sliderPanel: AppState.Panel? = d.liveSlider ?? ((d.panel == .brightness || d.panel == .volume) ? d.panel : nil)
        ZStack {
            AmbientLight(color: d.appColor, isSiriActive: d.isSiriActive, style: d.backdrop, image: d.backdropImage)
            HStack(spacing: Metrics.spacing) {
                if d.showsEsc {
                    // while a temporary panel (emoji, tabs, Now Playing…) is open, "Done" like the original: closes the panel, sends no key
                    let showsDone = d.panel == .emoji || d.panel == .tabs || d.panel == .nowPlaying
                    GlassButton(width: Metrics.escWidth, highlight: showsDone ? .white.opacity(0.22) : nil, action: showsDone ? d.handleEsc : d.esc) {
                        if showsDone { BarText("Done") } else { Text("esc").kerning(0.3) }
                    }
                        .transition(.focusIn)
                }
                MainArea(d: d).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 3)
            .opacity(sliderPanel == nil && d.popover == nil ? 1 : 0)
            // while pressing and sliding the button stays in the hierarchy so the finger's movement isn't cut off
            .allowsHitTesting((sliderPanel == nil && d.popover == nil) || d.liveSlider != nil || d.isDraggingPopover)
            if let k = sliderPanel {
                PopUpSlider(d: d, k: k, isClosable: d.liveSlider == nil)
                    .transition(.opacity)
            }
            if let a = d.popover, sliderPanel == nil {
                PopoverView(d: d, a: a)
                    .padding(.horizontal, 3)
                    .transition(.focusIn)
            }
        }
        .overlay {
            // warm tint: pulls white toward amber, leaves black unchanged
            let g = d.colorTemperature.intensity(nightShift: d.isNightShiftOn)
            if g > 0 {
                Color(red: 1, green: 1 - 0.16 * g, blue: 1 - 0.42 * g)
                    .blendMode(.multiply).allowsHitTesting(false)
            }
        }
        .frame(width: d.width, height: Metrics.barHeight)
        .coordinateSpace(name: "bar")
        .background(Color.black)
        .environment(\.theme, d.theme)
        .font(.system(size: 14))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: d.animationKey)
    }
}

/// The area after esc: temporary panels first, otherwise the configured bar mode.
struct MainArea: View {
    @ObservedObject var d: AppState

    var body: some View {
        if d.isEditingControlStrip { ControlStripEditor(d: d).transition(.focusIn) } else { currentPanel }
    }

    @ViewBuilder private var currentPanel: some View {
        switch d.panel {
        case .expanded: ExpandedControlStrip(d: d, isClosable: true).transition(.focusIn)
        case .nowPlaying: NowPlayingBar(d: d).transition(.focusIn)
        case .tabs: TabsBar(d: d).transition(.focusIn)
        case .emoji: EmojiBar(d: d).transition(.focusIn)
        case .app, .brightness, .volume:
            if d.screenshotTool != nil && !d.fn {
                WithControlStrip(d: d) { ScreenshotBar(d: d) }.transition(.focusIn)
            } else {
            switch d.activeBarMode {
            case .fKeys: FunctionKeysRow(d: d).transition(.focusIn)
            case .expanded: ExpandedControlStrip(d: d, isClosable: false).transition(.focusIn)
            case .spaces: WithControlStrip(d: d) { SpacesRow(d: d) }.transition(.focusIn)
            case .quickActions: WithControlStrip(d: d) { QuickActionsRow(d: d) }.transition(.focusIn)
            case .app: WithControlStrip(d: d) { AppArea(d: d) }.transition(.focusIn)
            }
            }
        }
    }
}

/// Content + collapsed Control Strip on the right; the Siri pill and the press-and-slide slider float over the content.
struct WithControlStrip<Content: View>: View {
    @ObservedObject var d: AppState
    @ViewBuilder var content: () -> Content

    var body: some View {
        let isCovered = d.isSiriActive
        HStack(spacing: Metrics.spacing) {
            ZStack {
                content()
                    // the content only recedes slightly so the glass drop shows it refracted behind
                    .blur(radius: isCovered ? 1 : 0)
                    .opacity(isCovered ? 0.55 : 1)
                    .allowsHitTesting(!isCovered)
                if d.isSiriActive {
                    Button(action: d.stopSiri) { SiriPill() }
                        .buttonStyle(.plain)
                        .transition(.dropIn)
                }
            }
            if d.showsControlStrip { CollapsedControlStrip(d: d) }
        }
    }
}

/// The light behind the glass: the drifting is in Core Animation (AnimatedLayers.swift), the touch light in SwiftUI.
/// Behind the glass ("Background" in the menu): when off, only a faint white glow on touch; with light styles, three
/// slowly drifting color blobs; with wallpaper/image, a dimmed image strip. While Siri listens the light turns to Siri's colors; with the background off there's no light at all.
struct AmbientLight: View {
    let color: Color
    let isSiriActive: Bool
    let style: Backdrop
    let image: NSImage?
    @ObservedObject private var light = TouchLight.shared

    var body: some View {
        ZStack {
            if style.isImage, let image {
                Image(nsImage: image).resizable()
                    .blur(radius: 1.5)
                    .overlay(Color.black.opacity(0.4))
                if isSiriActive { AmbientLayer(colors: SiriColors.all.dropFirst().map { NSColor($0) }).opacity(0.7) }
            } else if style != .off {
                AmbientLayer(colors: isSiriActive ? SiriColors.all.dropFirst().map { NSColor($0) } : (style.colors ?? [NSColor(color)]))
            }
            touchGlow
        }
        .allowsHitTesting(false)
    }

    /// Light seeping through the glass behind the touched button.
    @ViewBuilder private var touchGlow: some View {
        if style == .off {
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.12), .white.opacity(0.05), .clear],
                                     center: .center, startRadius: 0, endRadius: 55))
                .frame(width: 110, height: 70)
                .position(light.position)
                .opacity(light.intensity)
        } else {
            let c = style.colors.map { Color(nsColor: $0[0]) } ?? color
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), c.opacity(0.6), .clear],
                                     center: .center, startRadius: 0, endRadius: 45))
                .frame(width: 110, height: 70)
                .position(light.position)
                .opacity(light.intensity)
                .blur(radius: 8)
                .blendMode(.plusLighter)
        }
    }
}

// MARK: Control Strip
struct SiriButton: View {
    @ObservedObject var d: AppState
    var body: some View {
        GlassButton(width: Metrics.iconWidth, action: d.toggleSiri) { SiriOrb(isActive: d.isSiriActive) }
    }
}

struct CollapsedControlStrip: View {
    @ObservedObject var d: AppState
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            GlassButton("chevron.left", width: Metrics.narrowWidth, action: d.expand)
            if let c = d.nowPlaying { NowPlayingButton(d: d, c: c).transition(.focusIn) }
            ForEach(d.stripButtons, id: \.self) { StripButtonView(d: d, t: $0) }
        }
    }
}

/// Touch Bar counterpart of the original "Customize Control Strip": buttons on the left are in the strip
/// (drag to reorder, tap to remove), buttons on the right can be added (tap to append).
struct ControlStripEditor: View {
    @ObservedObject var d: AppState
    @StateObject private var s = StripDrag()

    var body: some View {
        let available = StripButton.allCases.filter { !d.stripButtons.contains($0) }
        let step = Metrics.iconWidth + Metrics.spacing
        HStack(spacing: Metrics.spacing) {
            GlassButton(width: Metrics.escWidth, highlight: Color(hex: 0x0A84FF, 0.6), action: { d.isEditingControlStrip = false }) { BarText("Done") }
            HStack(spacing: Metrics.spacing) {
                ForEach(d.stripButtons, id: \.self) { t in
                    let isDragged = s.button == t
                    GlassButton(t.symbol, action: { d.stripButtons.removeAll { $0 == t } })
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 10))
                                .foregroundStyle(.white, Color(hex: 0xFF453A)).offset(x: 2, y: -1)
                        }
                        .offset(x: isDragged ? s.x : 0)
                        .zIndex(isDragged ? 1 : 0)
                        .scaleEffect(isDragged ? 1.08 : 1)
                        .simultaneousGesture(DragGesture(minimumDistance: 8)
                            .onChanged { e in
                                s.button = t
                                s.x = e.translation.width
                                // swap places once the finger has moved one button width
                                guard let i = d.stripButtons.firstIndex(of: t) else { return }
                                let j = min(max(0, i + Int((s.x / step).rounded())), d.stripButtons.count - 1)
                                if j != i {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        d.stripButtons.move(fromOffsets: [i], toOffset: j > i ? j + 1 : j)
                                    }
                                    s.x -= CGFloat(j - i) * step
                                }
                            }
                            .onEnded { _ in withAnimation(.spring(response: 0.3)) { s.button = nil; s.x = 0 } })
                }
            }
            .padding(.horizontal, 4)
            .background(Capsule().fill(.white.opacity(0.08)))
            Text(L(d.stripButtons.count >= StripButton.maxCount ? "Strip full" : "Add:"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
            ScrollingStrip {
                ForEach(available, id: \.self) { t in
                    GlassButton(t.symbol, action: {
                        guard d.stripButtons.count < StripButton.maxCount else { return }
                        d.stripButtons.append(t)
                    })
                    .inScrollingStrip()
                    .opacity(d.stripButtons.count < StripButton.maxCount ? 1 : 0.4)
                }
            }
        }
    }
}

final class StripDrag: ObservableObject {
    @Published var button: StripButton?
    @Published var x: CGFloat = 0
}

struct StripButtonView: View {
    @ObservedObject var d: AppState
    let t: StripButton

    var body: some View {
        switch t {
        case .siri: SiriButton(d: d)
        case .brightness:
            GlassButton("sun.max.fill") { d.performStripButton(.brightness) }
                .whenSliding({ d.liveSlide(.brightness, $0) }, onEnd: d.endLiveSlider)
                .modifier(ReportButtonFrame(d: d, k: .brightness))
        case .volume:
            GlassButton(d.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") { d.performStripButton(.volume) }
                .whenSliding({ d.liveSlide(.volume, $0) }, onEnd: d.endLiveSlider)
                .modifier(ReportButtonFrame(d: d, k: .volume))
        case .mute: GlassButton("speaker.slash.fill", highlight: d.isMuted ? .white.opacity(0.35) : nil) { d.performStripButton(.mute) }
        case .nightShift: GlassButton("moon.stars.fill", highlight: d.isNightShiftOn ? Color(hex: 0xF5A623, 0.6) : nil) { d.performStripButton(.nightShift) }
        case .inputSource: GlassButton(action: { d.performStripButton(.inputSource) }) { Text(d.inputSourceName).font(.system(size: 12, weight: .semibold)) }
        default: GlassButton(t.symbol) { d.performStripButton(t) }
        }
    }
}

/// Now Playing button that appears in the strip while something plays.
struct NowPlayingButton: View {
    @ObservedObject var d: AppState
    let c: NowPlaying
    var body: some View {
        GlassButton(width: 52, action: { d.panel = .nowPlaying }) {
            HStack(spacing: 4) {
                AppIcon(bundleID: c.source, size: 15)
                Image(systemName: c.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11))
            }
        }
    }
}

struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 20
    private static var cache: [String: NSImage] = [:]

    private var icon: NSImage? {
        if let s = AppIcon.cache[bundleID] { return s }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let s = NSWorkspace.shared.icon(forFile: url.path)
        AppIcon.cache[bundleID] = s
        return s
    }

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "music.note")
        }
    }
}

struct ExpandedControlStrip: View {
    @ObservedObject var d: AppState
    var isClosable = true
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            if isClosable { GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse) }
            ButtonGroup(buttons: [.init(symbol: "sun.min.fill") { d.step(.brightnessDown) },
                          .init(symbol: "sun.max.fill") { d.step(.brightnessUp) }])
            GlassButton("rectangle.3.group", action: SystemControl.missionControl)
            GlassButton("square.grid.3x3.fill", action: SystemControl.launchpad)
            ButtonGroup(buttons: [.init(symbol: "light.min") { d.step(.backlightDown) },
                          .init(symbol: "light.max") { d.step(.backlightUp) }])
            ButtonGroup(buttons: [.init(symbol: "backward.fill") { d.step(.previous) },
                          .init(symbol: "playpause.fill") { d.step(.playPause) },
                          .init(symbol: "forward.fill") { d.step(.next) }])
            ButtonGroup(buttons: [.init(symbol: "speaker.slash.fill", highlight: d.isMuted ? .white.opacity(0.3) : nil) { d.toggleMute() },
                          .init(symbol: "speaker.wave.1.fill") { d.step(.volumeDown) },
                          .init(symbol: "speaker.wave.3.fill") { d.step(.volumeUp) }])
            SiriButton(d: d)
        }
    }
}

/// Stores the button's frame in the bar; the pop-up slider opens just to its left.
struct ReportButtonFrame: ViewModifier {
    let d: AppState
    let k: AppState.Panel
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { d.buttonFrames[k] = g.frame(in: .named("bar")) }
                .onChange(of: g.frame(in: .named("bar"))) { _, r in d.buttonFrames[k] = r }
        })
    }
}

/// Brightness/volume slider with the original dimensions: a 360 pt box just left of the button; after a tap
/// a ✕ appears in place of the button, not while pressing and sliding. The rest of the bar dims.
struct PopUpSlider: View {
    @ObservedObject var d: AppState
    let k: AppState.Panel
    let isClosable: Bool
    static let width: CGFloat = 360

    var body: some View {
        let isBrightness = k == .brightness
        let buttonFrame = d.buttonFrames[k] ?? CGRect(x: d.width - (isBrightness ? 220 : 160), y: 2, width: Metrics.iconWidth, height: Metrics.buttonHeight)
        let trailingX = buttonFrame.midX - 28, boxWidth = PopUpSlider.width
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                // the end icons also step down/up by one, like the original
                Image(systemName: isBrightness ? "sun.min.fill" : "speaker.fill").font(.system(size: 12))
                    .frame(width: 30, height: Metrics.buttonHeight).contentShape(Rectangle())
                    .onTapGesture { d.sliderStep(k, -1) }
                if isBrightness {
                    GlassSlider(value: $d.brightness, fillColor: Color(hex: 0x0A84FF), onValueChange: d.setBrightness)
                } else {
                    GlassSlider(value: $d.volume, fillColor: Color(hex: 0x0A84FF), onValueChange: d.setVolume)
                }
                Image(systemName: isBrightness ? "sun.max.fill" : "speaker.wave.3.fill").font(.system(size: 14))
                    .frame(width: 30, height: Metrics.buttonHeight).contentShape(Rectangle())
                    .onTapGesture { d.sliderStep(k, 1) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(width: boxWidth, height: Metrics.buttonHeight)
            .background(GlassBackground())
            .allowsHitTesting(isClosable)
            .position(x: max(boxWidth / 2 + 3, trailingX - boxWidth / 2), y: Metrics.barHeight / 2)
            .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            if isClosable {
                GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse)
                    .position(x: buttonFrame.midX, y: Metrics.barHeight / 2)
                    .transition(.focusIn)
            }
        }
        .frame(width: d.width, height: Metrics.barHeight)
    }
}

struct FunctionKeysRow: View {
    @ObservedObject var d: AppState
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            ForEach(1...12, id: \.self) { i in
                GlassButton(width: nil, action: { d.pressFunctionKey(i) }) { BarText("F\(i)").frame(maxWidth: .infinity) }
            }
        }
    }
}

/// The "Spaces" bar mode.
/// The original "Touch Bar Shows: Quick Actions": the enabled items in the front app's Services menu.
final class QuickActionsModel: ObservableObject {
    @Published var items: [String]?
}

struct QuickActionsRow: View {
    @ObservedObject var d: AppState
    @StateObject private var h = QuickActionsModel()
    private var items: [String]? { h.items }
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            GlassButton("gearshape.2", action: load)
            if let items, !items.isEmpty {
                ScrollingStrip {
                    ForEach(items, id: \.self) { t in
                        GlassButton(width: nil, action: { select(t) }) {
                            Text(t).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 180)
                        }
                        .inScrollingStrip()
                    }
                }
            } else {
                Text(L(items == nil ? "Loading…" : "Nothing to choose right now"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: load)
        .onChange(of: d.frontBundleID) { _, _ in load() }
    }

    private func load() {
        guard let pid = d.frontApp?.processIdentifier else { h.items = []; return }
        SystemControl.workQueue.async {
            let l = AX.submenuTitles(pid, identifier: nil, titles: ["Servisler", "Services"])
            DispatchQueue.main.async { h.items = l }
        }
    }

    private func select(_ t: String) {
        guard let pid = d.frontApp?.processIdentifier else { return }
        SystemControl.workQueue.async { AX.pressSubmenuItem(pid, identifier: nil, titles: ["Servisler", "Services"], t) }
    }
}

struct SpacesRow: View {
    @ObservedObject var d: AppState
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            GlassButton("rectangle.3.group", action: SystemControl.missionControl)
            ForEach(0..<d.spaces.count, id: \.self) { i in
                GlassButton(width: nil, highlight: i == d.spaces.current ? .white.opacity(0.28) : nil, action: { Spaces.switchTo(i) }) {
                    Text(String(format: L("Desktop %d"), i + 1)).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: Now Playing
struct NowPlayingBar: View {
    @ObservedObject var d: AppState
    var body: some View {
        HStack(spacing: Metrics.spacing) {
            GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse)
            if let c = d.nowPlaying {
                GlassButton(action: { SystemControl.openApp(c.source) }) { AppIcon(bundleID: c.source) }
                PlayerControls(d: d, c: c)
            }
            SiriButton(d: d)
        }
    }
}

/// Previous/play/next + a filmstrip with thumbnails for video, a track bar for music.
struct PlayerControls: View {
    @ObservedObject var d: AppState
    let c: NowPlaying
    var body: some View {
        if c.source == NowPlaying.spotify && d.showsSpotifyPlayer {
            SpotifyPlayer(d: d, c: c)
        } else {
            standardControls
        }
    }

    @ViewBuilder private var standardControls: some View {
        ButtonGroup(buttons: [.init(symbol: c.video ? "gobackward.15" : "backward.fill") { d.nowPlayingCommand { $0.previous() } },
                      .init(symbol: c.isPlaying ? "pause.fill" : "play.fill") { d.nowPlayingCommand { $0.playPause() } },
                      .init(symbol: c.video ? "goforward.15" : "forward.fill") { d.nowPlayingCommand { $0.next() } }],
             buttonWidth: Metrics.narrowWidth + 2)
        if c.video {
            FilmstripView(d: d)
            Text(TimeFormat.typeText(Double(d.nowPlayingProgress) * c.duration) + " / " + TimeFormat.typeText(c.duration))
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        } else {
            TrackProgress(d: d, c: c)
            if c.source == NowPlaying.music { GlassButton("heart") { c.love() } }
        }
    }
}

enum TimeFormat {
    static func typeText(_ s: Double) -> String {
        let s = Int(max(0, s))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct TrackProgress: View {
    @ObservedObject var d: AppState
    let c: NowPlaying
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(c.name).fontWeight(.semibold) + Text(c.artist.isEmpty ? "" : "  ·  \(c.artist)").foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(TimeFormat.typeText(Double(d.nowPlayingProgress) * c.duration)) / \(TimeFormat.typeText(c.duration))").monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 10))
            .lineLimit(1)
            GlassSlider(value: $d.nowPlayingProgress, isThin: true, onValueChange: { d.scrubNowPlaying($0) }).frame(height: 10)
        }
        .padding(.horizontal, 10)
    }
}

/// Scrubbing over the QuickTime video's thumbnails; the playhead turns into a glass lens while dragged.
struct FilmstripView: View {
    enum Source { case quickTime, photos, safari }
    @ObservedObject var d: AppState
    let source: Source
    @ObservedObject private var filmstrip: Filmstrip
    @StateObject private var b = PressState()

    init(d: AppState, source: Source = .quickTime) {
        self.d = d
        self.source = source
        _filmstrip = ObservedObject(wrappedValue: source == .photos ? Filmstrip.photos : source == .safari ? Filmstrip.safari : Filmstrip.shared)
    }

    private var position: Float {
        get {
            switch source {
            case .quickTime: d.nowPlayingProgress
            case .photos: d.photosVideo?.position ?? 0
            case .safari: d.safariVideo?.position ?? 0
            }
        }
        nonmutating set {
            switch source {
            case .quickTime: d.nowPlayingProgress = newValue
            case .photos: d.photosVideo?.position = newValue
            case .safari: d.safariVideo?.position = newValue
            }
        }
    }

    private func scrub(_ v: Float, force: Bool = false) {
        switch source {
        case .quickTime: d.scrubNowPlaying(v, force: force)
        case .photos: d.scrubPhotosVideo(v, force: force)
        case .safari: d.scrubSafariVideo(v, force: force)
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), x = CGFloat(position) * w
            let n = max(1, filmstrip.images.count)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.08))
                    HStack(spacing: 0) {
                        ForEach(Array(filmstrip.images.enumerated()), id: \.offset) { _, r in
                            Image(nsImage: r).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: w / CGFloat(n), height: 24).clipped()
                        }
                    }
                    // the played part is slightly brighter, the rest dim
                    Rectangle().fill(.black.opacity(0.35)).frame(width: max(0, w - x)).offset(x: x)
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                // playhead
                ZStack {
                    Capsule().fill(.white.opacity(b.isPressed ? 0.1 : 0.9))
                    Capsule().strokeBorder(.white.opacity(0.95), lineWidth: b.isPressed ? 1.2 : 0)
                    Capsule().fill(LinearGradient(colors: [.white.opacity(b.isPressed ? 0.5 : 0), .clear], startPoint: .top, endPoint: .center))
                        .padding(2)
                }
                .frame(width: b.isPressed ? 18 : 3, height: b.isPressed ? 29 : 28)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .shadow(color: .white.opacity(b.isPressed ? 0.4 : 0), radius: 6)
                .offset(x: x - (b.isPressed ? 9 : 1.5))
                .animation(b.isPressed ? Springs.press : Springs.release, value: b.isPressed)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    b.isPressed = true
                    withAnimation(Springs.follow) { position = Float(min(1, max(0, e.location.x / w))) }
                    scrub(position)
                }
                .onEnded { _ in
                    b.isPressed = false
                    scrub(position, force: true)
                })
        }
        .frame(height: Metrics.buttonHeight)
    }
}

// MARK: screenshot (⇧⌘5)
/// Like the original: three capture and three record buttons on the left (the selected one lit), "Save to: Desktop ›" on the right.
/// Tapping the save location replaces it with the list of options.
struct ScreenshotBar: View {
    @ObservedObject var d: AppState
    var body: some View {
        let a = d.screenshotTool ?? ScreenshotTool()
        HStack(spacing: Metrics.spacing) {
            if d.showsTargetList {
                GlassButton("chevron.left", width: Metrics.narrowWidth) { d.showsTargetList = false }
                ButtonGroup(buttons: ScreenshotTool.targets.map { h in
                    .init(text: h, highlight: h == a.target ? .white.opacity(0.25) : nil) { d.selectScreenshotTarget(h) }
                })
                .frame(maxWidth: .infinity)
            } else {
                ButtonGroup(buttons: ScreenshotTool.captureModes.map { k in
                    .init(symbol: k.identifier, highlight: !a.video && a.style == k.style ? .white.opacity(0.25) : nil) {
                        d.selectScreenshotMode(k.identifier, style: k.style, video: false)
                    }
                }, buttonWidth: Metrics.iconWidth)
                ButtonGroup(buttons: ScreenshotTool.recordModes.map { k in
                    .init(symbol: ScreenshotTool.symbol(k.identifier), highlight: a.video && a.style == k.style ? .white.opacity(0.25) : nil) {
                        d.selectScreenshotMode(k.identifier, style: k.style, video: true)
                    }
                }, buttonWidth: Metrics.iconWidth)
                Spacer(minLength: 0)
                BarText("Save to:", weight: .regular).foregroundStyle(.white.opacity(0.85))
                GlassButton(width: nil, action: { d.showsTargetList = true }) {
                    HStack(spacing: 6) {
                        Text(L(a.target)).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(minWidth: 90)
                }
            }
        }
    }
}

// MARK: Safari tabs
/// Safari's windows and tabs: numbered buttons when there are several windows, then that window's tabs.
/// Tapping a tab switches to it; the strip scrolls.
struct TabsBar: View {
    @ObservedObject var d: AppState
    var body: some View {
        let windows = Array(Set(d.tabs.map(\.window))).sorted()
        let items = d.tabs.filter { $0.window == d.selectedWindow }
        HStack(spacing: Metrics.spacing) {
            GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse)
            if windows.count > 1 {
                ButtonGroup(buttons: windows.map { p in
                    .init(text: "\(p)", highlight: p == d.selectedWindow ? .white.opacity(0.25) : nil) { d.selectedWindow = p }
                }, buttonWidth: 28)
            }
            if items.isEmpty {
                Text(L(d.isLoadingTabs ? "Loading tabs…"
                     : d.isSafariAccessDenied ? "No access to Safari: System Settings → Privacy & Security → Automation"
                     : "No open Safari windows"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
                Spacer(minLength: 0)
            } else {
                ScrollingStrip {
                    ForEach(items) { s in
                        GlassButton(width: nil, highlight: s.isSelected ? .white.opacity(0.28) : nil, action: { d.selectTab(s) }) {
                            Text(s.name.isEmpty ? s.address : s.name)
                                .font(.system(size: 12, weight: s.isSelected ? .semibold : .regular))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 150)
                        }
                        .inScrollingStrip()
                        .selectedInStrip(s.isSelected)
                    }
                }
                .id(d.selectedWindow)
            }
            GlassButton("square.grid.2x2") { d.shortcut(42, [.maskCommand, .maskShift], "\\") }
            GlassButton("plus") { d.shortcut(17, .maskCommand, "t"); d.refreshTabsSoon() }
        }
    }
}

// MARK: emoji
struct EmojiBar: View {
    @ObservedObject var d: AppState
    var body: some View {
        let categories = Emoji.categories
        let items = d.emojiCategory == 0 ? Emoji.recents : categories[d.emojiCategory].emojis
        HStack(spacing: Metrics.spacing) {
            GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse)
            ButtonGroup(buttons: categories.indices.map { i in
                .init(symbol: categories[i].symbol, highlight: i == d.emojiCategory ? .white.opacity(0.25) : nil) { d.emojiCategory = i }
            }, buttonWidth: 30)
            ScrollingStrip {
                ForEach(items, id: \.self) { e in
                    Text(e).font(.system(size: 19)).frame(width: 34)
                        .modifier(LiquidPress(kind: .bubble, isScrollable: true, action: { Emoji.insert(e) }))
                        .frame(height: Metrics.buttonHeight)
                }
            }
            .id(d.emojiCategory)
        }
    }
}

// MARK: app area
/// In a narrow area (many buttons in the Control Strip), text labels turn into icons first, then the app icon hides.
private struct CompactLevelKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var compactLevel: Int {
        get { self[CompactLevelKey.self] }
        set { self[CompactLevelKey.self] = newValue }
    }
}

struct AppArea: View {
    @ObservedObject var d: AppState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            area(0)
            area(1).environment(\.compactLevel, 1)
            area(2).environment(\.compactLevel, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func area(_ compactLevel: Int) -> some View {
        HStack(spacing: Metrics.spacing) {
            // switching to the front app's own Touch Bar controls: on long press, so an accidental tap doesn't close the bar
            if compactLevel < 2 {
            GlassButton(width: Metrics.iconWidth, action: {}) {
                if let icon = d.frontApp?.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in d.showAppOwnControls() })
            }
            if d.showsSpotifyHere, let c = d.nowPlaying {
                PlayerControls(d: d, c: c)
            } else {
            switch d.frontBundleID {
            case "com.apple.Safari": SafariControls(d: d)
            case "com.apple.Notes": NotesControls(d: d)
            case NowPlaying.music, NowPlaying.spotify, NowPlaying.quickTime: MediaAppControls(d: d)
            case "com.apple.finder": FinderControls(d: d)
            case "com.apple.mail": MailControls(d: d)
            case "com.apple.calculator": CalculatorControls(d: d)
            case "com.apple.iCal": CalendarControls(d: d)
            case "com.apple.reminders":
                GlassButton("plus") { d.shortcut(45, .maskCommand, "n") }
                Spacer(minLength: 0)
            case Contact.bundleID: ContactsControls(d: d)
            case "com.apple.Preview": PreviewControls(d: d)
            case "com.apple.Photos": PhotosControls(d: d)
            case "com.apple.MobileSMS":
                GlassButton("square.and.pencil") { d.shortcut(45, .maskCommand, "n") }
                TapbackButton(d: d)
                TypingControls(d: d)
            case "com.apple.TextEdit":
                TextFormatControls(d: d)
                TypingControls(d: d)
            default:
                // while a text field is focused, like the original: emoji on the left, suggestions on the right
                GlassButton("face.smiling") { d.panel = .emoji }
                if d.suggestions.isActive {
                    Spacer(minLength: 0)
                    SuggestionStrip(d: d)
                } else {
                    Text(d.frontApp?.localizedName ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 6)
                    Spacer(minLength: 0)
                }
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Typing suggestions with the original dimensions: three boxes, 375 pt wide, hidden with ">". With a partial word the first
/// box is the typed text itself (in quotes; choosing it only adds a space), corrections in blue.
struct SuggestionStrip: View {
    @ObservedObject var d: AppState
    var body: some View {
        if d.suggestionsHidden {
            GlassButton(width: 46, action: { d.suggestionsHidden = false }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                    Image(systemName: "keyboard")
                }
            }
        } else {
            HStack(spacing: Metrics.spacing) {
                GlassButton("chevron.right", width: Metrics.narrowWidth) { d.suggestionsHidden = true }
                ButtonGroup(buttons: suggestionButtons, backgroundTint: Color(hex: 0x2A3A50)).frame(width: 375)
                    .animation(.easeInOut(duration: 0.18), value: d.suggestions)
            }
        }
    }

    private var suggestionButtons: [GroupButton] {
        let o = d.suggestions
        var t: [GroupButton] = []
        if !o.partialWord.isEmpty { t.append(.init(text: "“\(o.partialWord)”") { SystemControl.typeText(" ") }) }
        for (i, k) in o.words.enumerated() {
            t.append(.init(text: k, highlight: o.isCorrection && i == 0 ? Color(hex: 0x0A84FF, 0.6) : nil) { d.selectSuggestion(k) })
        }
        while t.count < 3 { t.append(.init(text: "") {}) }
        return t
    }
}

struct MediaAppControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        if let c = d.nowPlaying, c.source == d.frontBundleID {
            PlayerControls(d: d, c: c)
            if d.frontBundleID == NowPlaying.music {
                GlassButton("text.line.first.and.arrowtriangle.forward") { d.menu(nil, "Sıradaki Olarak Çal", "Sonra Çal") }
            }
        } else {
            Text(L(d.frontBundleID == NowPlaying.quickTime ? "No open video" : "Nothing playing"))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
            Spacer(minLength: 0)
        }
    }
}

struct SafariControls: View {
    @ObservedObject var d: AppState
    @Environment(\.theme) private var theme
    var body: some View {
        if let v = d.safariVideo {
            SafariVideoBar(d: d, v: v)
        } else {
            normal
        }
    }

    @ViewBuilder private var normal: some View {
        ButtonGroup(buttons: [.init(symbol: "chevron.left") { d.shortcut(33, .maskCommand, "[") },
                      .init(symbol: "chevron.right") { d.shortcut(30, .maskCommand, "]") }],
             buttonWidth: Metrics.narrowWidth)
        GlassButton(width: nil, action: { d.shortcut(37, .maskCommand, "l") }) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(L("Search or enter website name")).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        GlassButton("square.on.square", action: d.showTabs)
        // in the minimal theme the primary action is tinted (Apple: tint only the primary action)
        GlassButton("plus", highlight: theme == .minimal ? Color(hex: 0x0A84FF) : nil) { d.shortcut(17, .maskCommand, "t") }
    }
}

/// While a video plays in Safari (like the original): play/pause, ±10 s, a scrubbing strip with thumbnails, time,
/// and the address bar on the far right (to search without leaving the video).
struct SafariVideoBar: View {
    @ObservedObject var d: AppState
    let v: SafariVideo
    var body: some View {
        ButtonGroup(buttons: [.init(symbol: "gobackward.10") { d.skipSafariVideo(-10) },
                      .init(symbol: v.isPaused ? "play.fill" : "pause.fill") { d.toggleSafariVideo() },
                      .init(symbol: "goforward.10") { d.skipSafariVideo(10) }],
             buttonWidth: Metrics.narrowWidth + 2)
        FilmstripView(d: d, source: .safari)
        Text(TimeFormat.typeText(v.elapsed) + " / " + TimeFormat.typeText(v.duration))
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        GlassButton("magnifyingglass") { d.shortcut(37, .maskCommand, "l") }
    }
}

struct NotesControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        if d.suggestions.isActive {
            GlassButton("checklist") { d.menu(nil, "Yapılacaklar Listesi") }
            PopoverButton(d: d, popover: {
                Popover(items: [PopoverItem(text: "Title") { d.menu(nil, "Ana Başlık") },
                                PopoverItem(text: "Heading") { d.menu(nil, "Başlık") },
                                PopoverItem(text: "Subheading") { d.menu(nil, "Alt Başlık") },
                                PopoverItem(text: "Body") { d.menu(nil, "Gövde") },
                                PopoverItem(symbol: "bold") { d.shortcut(11, .maskCommand, "b") },
                                PopoverItem(symbol: "italic") { d.shortcut(34, .maskCommand, "i") },
                                PopoverItem(symbol: "underline") { d.shortcut(32, .maskCommand, "u") }])
            }) { Image(systemName: "textformat") }
            PopoverButton(d: d, popover: {
                Popover(items: [PopoverItem(symbol: "list.bullet") { d.menu(nil, "Madde İşaretli Liste") },
                                PopoverItem(symbol: "list.dash") { d.menu(nil, "Tire İşaretli Liste") },
                                PopoverItem(symbol: "list.number") { d.menu(nil, "Numaralı Liste") }])
            }) { Image(systemName: "list.bullet") }
            GlassButton("face.smiling") { d.panel = .emoji }
            Spacer(minLength: 0)
            SuggestionStrip(d: d)
        } else {
            GlassButton("square.and.pencil") { d.menu(nil, "Yeni Not") }
            GlassButton("checklist") { d.menu(nil, "Yapılacaklar Listesi") }
            GlassButton("trash") { d.menu(nil, "Sil") }
            GlassButton("list.bullet") { d.menu(nil, "Madde İşaretli Liste") }
            Spacer(minLength: 0)
        }
    }
}

/// Like the original: back/forward, view (popover), Quick Look in the middle, Share, Tags (popover color palette).
struct FinderControls: View {
    @ObservedObject var d: AppState
    // Finder tag order matches Finder.setLabel in SystemControl.swift
    private let tags: [(Color, Int)] = [(Color(hex: 0xFF453A), 2), (Color(hex: 0xFF9F0A), 1), (Color(hex: 0xFFD60A), 3),
                                             (Color(hex: 0x30D158), 6), (Color(hex: 0x0A84FF), 4), (Color(hex: 0xBF5AF2), 5),
                                             (Color(hex: 0x8E8E93), 7)]
    var body: some View {
        ButtonGroup(buttons: [.init(symbol: "chevron.left") { d.shortcut(33, .maskCommand, "[") },
                      .init(symbol: "chevron.right") { d.shortcut(30, .maskCommand, "]") }],
             buttonWidth: Metrics.iconWidth)
        PopoverButton(d: d, popover: {
            Popover(items: [PopoverItem(symbol: "square.grid.2x2") { d.shortcut(18, .maskCommand, "1") },
                            PopoverItem(symbol: "list.bullet") { d.shortcut(19, .maskCommand, "2") },
                            PopoverItem(symbol: "rectangle.split.3x1") { d.shortcut(20, .maskCommand, "3") },
                            PopoverItem(symbol: "squares.below.rectangle") { d.shortcut(21, .maskCommand, "4") }])
        }) { Image(systemName: "square.grid.2x2") }
        Spacer(minLength: 0)
        GlassButton("eye") { d.shortcut(49) }
        GlassButton("square.and.arrow.up") { d.menu(nil, "Paylaş…", "Paylaş") }
        PopoverButton(d: d, popover: {
            Popover(items: tags.map { color, index in PopoverItem(dot: color) { Finder.setLabel(index) } }
                   + [PopoverItem(symbol: "xmark.circle") { Finder.setLabel(0) }])
        }) { Image(systemName: "tag") }
        Spacer(minLength: 0)
    }
}

/// Like the original: New Message, Reply (press and slide for Reply All / Forward), Archive,
/// "Move to…" (mailboxes), Delete, Flag (colors). Menu items use Mail's language-independent identifiers.
struct MailControls: View {
    @ObservedObject var d: AppState
    @Environment(\.compactLevel) private var compactLevel
    private let m = "Mail.menuBar.messageMenu."
    var body: some View {
        // while composing, like the original: Send, attach a file, then typing suggestions
        if d.suggestions.isActive {
            GlassButton("paperplane.fill", highlight: Color(hex: 0x0A84FF, 0.6)) { d.menu(nil, "Gönder") }
            GlassButton("paperclip") { d.menu(nil, "Dosya Ekle…", "Dosyaları Ekle…") }
            TypingControls(d: d)
        } else {
            messageListControls
        }
    }

    @ViewBuilder private var messageListControls: some View {
        GlassButton("square.and.pencil") { d.menu("Mail.menuBar.fileMenu.newMessage") }
        PopoverButton(d: d, popover: {
            Popover(items: [PopoverItem(text: "Reply") { d.menu(m + "reply") },
                            PopoverItem(text: "Reply All") { d.menu(m + "replyAll") },
                            PopoverItem(text: "Forward") { d.menu(m + "forward") }])
        }, onTap: { d.menu(m + "reply") }) { Image(systemName: "arrowshape.turn.up.left") }
        GlassButton("archivebox") { d.menu(m + "archive") }
        GlassButton(width: nil, action: { d.showSubmenu(m + "moveTo", [], title: "Move to") }) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                if compactLevel == 0 { BarText("Move to…").opacity(0.85) }
            }
        }
        GlassButton("xmark.bin") { d.menu("Mail.menuBar.editMenu.delete") }
        GlassButton(action: { d.showSubmenu(m + "flag", [], title: "Flag") }) {
            Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xFF9F0A))
        }
    }
}

/// Like the original: ± % , on the left; ÷ × − + = in orange. Presses Calculator's own buttons.
struct CalculatorControls: View {
    @ObservedObject var d: AppState
    private let orange = Color(hex: 0xFF9F0A, 0.5)
    var body: some View {
        button("Negate") { Image(systemName: "plus.forwardslash.minus") }
        button("Percent") { Image(systemName: "percent") }
        button("Decimal") { Text(",").font(.system(size: 16, weight: .medium)) }
        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        button("Divide", orange) { Image(systemName: "divide") }
        button("Multiply", orange) { Image(systemName: "multiply") }
        button("Subtract", orange) { Image(systemName: "minus") }
        button("Add", orange) { Image(systemName: "plus") }
        button("Equals", orange) { Image(systemName: "equal") }
    }

    private func button<E: View>(_ identifier: String, _ color: Color? = nil, @ViewBuilder _ e: @escaping () -> E) -> some View {
        GlassButton(width: nil, highlight: color, action: { d.pressWindowButton(identifier) }) { e().frame(maxWidth: .infinity) }
    }
}

/// Like the original: "Today" and a scrolling strip of months; the shown month in red, outlined.
struct CalendarControls: View {
    @ObservedObject var d: AppState
    private static func formatter(_ b: Calendar.Component) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        f.setLocalizedDateFormatFromTemplate(b == .month ? "MMM" : b == .day ? "EEEd" : "dMMM")
        return f
    }

    var body: some View {
        let c = Calendar.current
        let b = d.calendarUnit
        let f = CalendarControls.formatter(b)
        let units = (b == .day ? -7...30 : -4...20).compactMap { c.date(byAdding: b, value: $0, to: d.calendarDate) }
        GlassButton(width: nil, action: d.showCalendarToday) { BarText("Today") }
        ScrollingStrip {
            ForEach(units, id: \.self) { t in
                let isSelected = c.isDate(t, equalTo: d.calendarDate, toGranularity: b)
                GlassButton(width: b == .month ? 84 : 92, action: { d.showCalendarDate(t) }) {
                    Text(f.string(from: t).replacingOccurrences(of: ".", with: ""))
                        .foregroundStyle(isSelected ? Color(hex: 0xFF453A) : .white)
                }
                .inScrollingStrip()
                .overlay(Capsule().strokeBorder(.white, lineWidth: isSelected ? 1.5 : 0))
            }
        }
        .id("\(d.calendarDate)\(b)")
    }
}

/// Like the original: new contact, message with the selected contact's name, call, FaceTime, email, Edit, Share.
struct ContactsControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        let k = d.contact
        GlassButton("plus") { d.shortcut(45, .maskCommand, "n") }
        GlassButton(width: nil, action: { k?.sendMessage() }) {
            HStack(spacing: 6) {
                Image(systemName: "message")
                Text(k?.name ?? "").lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(k == nil ? 0.4 : 1)
        GlassButton("phone") { k?.call() }.opacity(k?.phone.isEmpty ?? true ? 0.4 : 1)
        GlassButton("video") { k?.videoCall() }.opacity(k == nil ? 0.4 : 1)
        GlassButton("envelope") { k?.sendEmail() }.opacity(k?.email.isEmpty ?? true ? 0.4 : 1)
        GlassButton(width: nil, action: { d.shortcut(37, .maskCommand, "l") }) { BarText("Edit") }
        GlassButton("square.and.arrow.up") { d.menu(nil, "Kartı Paylaş…", "Kartı Paylaş", "Paylaş…", "Paylaş") }
    }
}

/// Like the original: adjustments on the left (popover), rotate left/right and flip horizontal/vertical in the middle.
struct PreviewControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        PopoverButton(d: d, popover: {
            Popover(items: [PopoverItem(text: "Markup") { d.menu(nil, "İşaretleme Araç Çubuğunu Göster", "İşaretleme Araç Çubuğunu Gizle") },
                            PopoverItem(text: "Adjust Color") { d.menu(nil, "Renk Ayarla…") },
                            PopoverItem(text: "Adjust Size") { d.menu(nil, "Boyutu Ayarla…") }])
        }) { Image(systemName: "slider.horizontal.3") }
        Spacer(minLength: 0)
        GlassButton("rotate.left") { d.menu(nil, "Sola Döndür") }
        GlassButton("rotate.right") { d.menu(nil, "Sağa Döndür") }
        GlassButton(action: { d.menu(nil, "Yatay Olarak Çevir") }) { Image(systemName: "flip.horizontal") }
        GlassButton(action: { d.menu(nil, "Düşey Olarak Çevir") }) { Image(systemName: "flip.horizontal").rotationEffect(.degrees(90)) }
        Spacer(minLength: 0)
    }
}

/// Like the original: Favorite, Auto Enhance, Rotate; with a video open, play/pause and a thumbnail strip
/// built from the video's frames (drag the playhead to scrub). The buttons are those in Photos' toolbar.
struct PhotosControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        GlassButton("heart") { d.pressWindowButton("IPXToolbarItemIDFavorite") }
        GlassButton("wand.and.rays") { d.pressWindowButton("IPXToolbarItemIDAutoEnhance") }
        GlassButton("rotate.left") { d.pressWindowButton("IPXToolbarItemIDRotate") }
        if let v = d.photosVideo {
            GlassButton("playpause.fill") { d.pressWindowButton("button_playPause") }
            FilmstripView(d: d, source: .photos)
            Text(v.elapsed + " / " + v.remaining.filter { $0 != "\u{200E}" })
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        } else {
            Spacer(minLength: 0)
        }
    }
}

/// Messages: Tapback for the selected message (can also be picked by pressing and sliding).
struct TapbackButton: View {
    @ObservedObject var d: AppState
    var body: some View {
        PopoverButton(d: d, popover: {
            Popover(items: ["❤️", "👍", "👎", "😂", "‼️", "❓"].enumerated().map { i, e in
                PopoverItem(text: e) { d.tapback(i + 1) }
            })
        }) { Image(systemName: "hand.thumbsup") }
    }
}

/// TextEdit: bold/italic/underline and alignment.
struct TextFormatControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        PopoverButton(d: d, popover: {
            Popover(items: [PopoverItem(symbol: "bold") { d.shortcut(11, .maskCommand, "b") },
                            PopoverItem(symbol: "italic") { d.shortcut(34, .maskCommand, "i") },
                            PopoverItem(symbol: "underline") { d.shortcut(32, .maskCommand, "u") },
                            PopoverItem(symbol: "text.alignleft") { d.menu(nil, "Sola Hizala") },
                            PopoverItem(symbol: "text.aligncenter") { d.menu(nil, "Ortala") },
                            PopoverItem(symbol: "text.alignright") { d.menu(nil, "Sağa Hizala") },
                            PopoverItem(symbol: "text.justify") { d.menu(nil, "İki Yana Yasla") }])
        }) { Image(systemName: "textformat") }
    }
}

/// In apps where you type: emoji, suggestions while typing, the app's name otherwise.
struct TypingControls: View {
    @ObservedObject var d: AppState
    var body: some View {
        GlassButton("face.smiling") { d.panel = .emoji }
        if d.suggestions.isActive {
            Spacer(minLength: 0)
            SuggestionStrip(d: d)
        } else {
            Text(d.frontApp?.localizedName ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
    }
}
