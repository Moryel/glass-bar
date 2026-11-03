import AppKit
import SwiftUI

// Theme Studio's canvas: the real built-in bars (Finder, Safari, Calculator, the Control Strip…) drawn with the draft
// on an AppState of their own. A clear layer on top catches every click and drop, so nothing on the canvas runs;
// buttons and sliders only report where they are and which part of the theme draws them.

enum StudioTarget: Hashable {
    case bar, button, group, slider
    case role(String)

    var title: String {
        switch self {
        case .bar: L("Bar")
        case .button: L("Button")
        case .group: L("Button group")
        case .slider: L("Slider")
        case .role(let k): Role.title(k)
        }
    }

    var help: String {
        switch self {
        case .bar: L("The background behind everything.")
        case .button: L("Every plain button on every bar.")
        case .group: L("Buttons that share one background, like back and forward.")
        case .slider: L("Brightness, volume and other sliders.")
        case .role(let k): Role.help(k)
        }
    }
}

struct StudioHit: Equatable {
    let frame: CGRect
    let target: StudioTarget
}

struct StudioHitsKey: PreferenceKey {
    static let defaultValue: [StudioHit] = []
    static func reduce(value: inout [StudioHit], nextValue: () -> [StudioHit]) { value += nextValue() }
}

private struct StudioInspectingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// true inside Theme Studio's canvas: buttons and sliders report their frames
    var studioInspecting: Bool {
        get { self[StudioInspectingKey.self] }
        set { self[StudioInspectingKey.self] = newValue }
    }
}

struct StudioHitReporter: View {
    let target: StudioTarget

    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: StudioHitsKey.self, value: [StudioHit(frame: g.frame(in: .named("studioCanvas")), target: target)])
        }
    }
}

/// The bars Theme Studio can show.
enum StudioScreen: String, CaseIterable, Identifiable {
    case finder, safari, mail, calculator, notes, music, calendar, contacts, preview, photos, messages, textEdit, otherApp
    case expanded, fKeys, spaces, quickActions, dock, emoji, widgets

    var id: String { rawValue }

    var bundleID: String? {
        switch self {
        case .finder: "com.apple.finder"
        case .safari: "com.apple.Safari"
        case .mail: "com.apple.mail"
        case .calculator: "com.apple.calculator"
        case .notes: "com.apple.Notes"
        case .music: NowPlaying.music
        case .calendar: "com.apple.iCal"
        case .contacts: Contact.bundleID
        case .preview: "com.apple.Preview"
        case .photos: "com.apple.Photos"
        case .messages: "com.apple.MobileSMS"
        case .textEdit: "com.apple.TextEdit"
        case .otherApp: "com.apple.Terminal"
        default: nil
        }
    }

    var name: String {
        switch self {
        case .expanded: L("Control Strip, expanded")
        case .fKeys: L("F1, F2 keys")
        case .spaces: L("Spaces")
        case .quickActions: L("Quick Actions")
        case .dock: L("Dock")
        case .emoji: L("Emoji")
        case .widgets: L("Widgets")
        case .otherApp: L("Any other app")
        default:
            bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? rawValue
        }
    }

    static let apps: [StudioScreen] = [.finder, .safari, .mail, .calculator, .notes, .music, .calendar, .contacts, .preview, .photos, .messages, .textEdit, .otherApp]
    static let system: [StudioScreen] = [.expanded, .fKeys, .spaces, .quickActions, .dock, .emoji, .widgets]
}

/// A full bar at its real width, scaled down to fit the window.
struct StudioCanvas: View {
    @ObservedObject var m: StudioModel
    @StateObject private var hover = HoverState()

    var body: some View {
        let t = m.draft
        let p = m.previewState
        GeometryReader { g in
            let scale = m.zoom > 0 ? m.zoom : min(1, g.size.width / p.width)
            ScrollView(.horizontal, showsIndicators: m.zoom > 0) {
            bar(t, p)
                .frame(width: p.width, height: Metrics.barHeight)
                .coordinateSpace(name: "studioCanvas")
                .background { if let b = t.skin?.bar { SkinBarBackground(style: b, theme: t) } else { Color.black } }
                .overlay { if let b = t.skin?.bar { SkinBarOverlay(style: b).allowsHitTesting(false) } }
                .environment(\.theme, t)
                .environment(\.studioInspecting, true)
                .font(t.font(14))
                .textCase(t.letterCase)
                .overlayPreferenceValue(StudioHitsKey.self) { hits in catcher(hits) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: p.width * scale, height: Metrics.barHeight * scale, alignment: .topLeading)
            }
            .scrollDisabled(m.zoom == 0)
        }
        .frame(height: Metrics.barHeight * (m.zoom > 0 ? m.zoom : 1) + (m.zoom > 0 ? 12 : 0))
    }

    @ViewBuilder private func bar(_ t: Theme, _ p: AppState) -> some View {
        HStack(spacing: Metrics.spacing) {
            if p.showsEsc { GlassButton(width: Metrics.escWidth, action: {}) { Text("esc").kerning(0.3) } }
            Group {
                switch m.screen {
                case .expanded: ExpandedControlStrip(d: p, isClosable: false)
                case .fKeys: FunctionKeysRow(d: p)
                case .spaces: WithControlStrip(d: p) { SpacesRow(d: p) }
                case .quickActions: WithControlStrip(d: p) { QuickActionsRow(d: p) }
                case .dock: WithControlStrip(d: p) { DockRow(d: p) }
                case .emoji: EmojiBar(d: p)
                case .widgets:
                    WithControlStrip(d: p, showsStrip: false) {
                        HStack(spacing: Metrics.spacing) {
                            ForEach(WidgetKind.stripKinds.filter { $0 != .nowPlaying }) { WidgetView(d: p, kind: $0) }
                            Spacer(minLength: 0)
                        }
                    }
                default: WithControlStrip(d: p) { AppArea(d: p) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 3)
    }

    /// Catches clicks, hovers and drops: the smallest element under the pointer wins, the bar itself when there's none.
    private func catcher(_ hits: [StudioHit]) -> some View {
        let shown = m.selected ?? hover.target
        return ZStack(alignment: .topLeading) {
            ForEach(Array(hits.enumerated()).filter { $0.element.target == shown }, id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: h.target == m.selected ? 2 : 1, dash: h.target == m.selected ? [] : [3, 2]))
                    .frame(width: h.frame.width + 4, height: h.frame.height + 4)
                    .offset(x: h.frame.minX - 2, y: h.frame.minY - 2)
            }
            if shown == .bar {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
            }
            Color.white.opacity(0.001)
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hover.target = target(at: p, hits) } else { hover.target = nil }
                }
                .onTapGesture(coordinateSpace: .local) { p in m.pick(target(at: p, hits)) }
                .dropDestination(for: String.self) { items, p in
                    guard let s = items.first else { return false }
                    m.apply(s, to: target(at: p, hits))
                    return true
                } isTargeted: { _ in }
        }
    }

    private func target(at p: CGPoint, _ hits: [StudioHit]) -> StudioTarget {
        hits.filter { $0.frame.insetBy(dx: -2, dy: -2).contains(p) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.target ?? .bar
    }
}

private final class HoverState: ObservableObject {
    @Published var target: StudioTarget?
}

/// Chips to drag onto the canvas, or click to apply to the selection.
struct StudioPalette: View {
    @ObservedObject var m: StudioModel

    static let colors = ["#FFFFFF", "#D1D1D6", "#8E8E93", "#3A3A3C", "#1C1C1E", "#000000", "#FF453A", "#FF9F0A", "#FFD60A",
                         "#30D158", "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#A2845E", "#F5EBDC", "#33FF66"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: $m.paint) {
                    Text(L("Fill")).tag("fill")
                    Text(L("Text")).tag("text")
                    Text(L("Border")).tag("borderColor")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                ForEach(m.themeColors + Self.colors, id: \.self) { c in
                    chip("\(m.paint):\(c)") { Circle().fill(Color(hexString: c) ?? .clear).overlay(Circle().strokeBorder(.secondary.opacity(0.4))) }
                        .frame(width: 16, height: 16)
                }
                ColorPicker("", selection: $m.customColor, supportsOpacity: false).labelsHidden()
                chip("\(m.paint):\(m.customColor.hexString)") {
                    RoundedRectangle(cornerRadius: 4).fill(m.customColor).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4)))
                }
                .frame(width: 22, height: 16)
            }
            HStack(spacing: 6) {
                ForEach(Self.styles, id: \.0) { s in
                    chip(s.0) { Text(L(s.1)).font(.caption).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(.secondary.opacity(0.15))) }
                }
            }
            Text(L("Click a part of the bar to edit it, or drag a chip onto it. Everything drawn by the same part changes together."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    static let styles = [("border:solid", "Solid"), ("border:dashed", "Dashed"), ("border:pixel", "Pixel"), ("border:ascii", "ASCII"),
                         ("border:sketch", "Hand-drawn"), ("border:none", "No border"), ("radius:0", "Square"), ("radius:6", "Rounded"),
                         ("radius:15", "Pill"), ("glow:4", "Glow"), ("glow:0", "No glow"), ("font:mono", "Mono"), ("font:rounded", "Rounded font"),
                         ("font:serif", "Serif"), ("font:system", "System font")]

    private func chip<C: View>(_ payload: String, @ViewBuilder _ label: () -> C) -> some View {
        label()
            .contentShape(Rectangle())
            .onTapGesture { m.apply(payload, to: m.selected ?? .button) }
            .draggable(payload)
            .help(L("Drag onto the bar, or click to apply to the selection"))
    }
}

/// The settings of the selected part, shown in the Selection tab.
struct StudioSelectionForm: View {
    @ObservedObject var m: StudioModel

    var body: some View {
        if let t = m.selected {
            Section {
                Text(t.title).font(.headline)
                Text(t.help).font(.caption).foregroundStyle(.secondary)
            }
            if m.draft.isSkin { skin(t) } else { glass(t) }
        } else {
            Section { Text(L("Click a part of the bar above to edit it.")).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func skin(_ t: StudioTarget) -> some View {
        switch t {
        case .bar:
            let b = m.skin(\.bar, empty: BarStyle())
            Section {
                OptionalColorRow(title: L("Color"), value: b.fill)
                OptionalColorRow(title: L("Gradient to"), value: b.fill2)
                Picker(L("Pattern"), selection: b.pattern) {
                    Text(L("None")).tag(String?.none)
                    Text(L("Stars")).tag(String?.some("stars"))
                    Text(L("Grid")).tag(String?.some("grid"))
                }
                Picker(L("Overlay"), selection: b.overlay) {
                    Text(L("None")).tag(String?.none)
                    Text(L("Scanlines")).tag(String?.some("scanlines"))
                }
            }
        case .button:
            Section(L("Normal")) { LayerEditor(p: m.skin(\.button, empty: LayerPatch())) }
            Section(L("Pressed")) { LayerEditor(p: m.skin(\.pressed, empty: LayerPatch())) }
        case .group:
            Section { LayerEditor(p: m.skin(\.group, empty: LayerPatch())) }
        case .slider:
            Section { OptionalColorRow(title: L("Slider color"), value: optional(\.sliderColor)) }
        case .role(let k):
            Section { LayerEditor(p: m.roleLayer(k)) }
        }
    }

    @ViewBuilder private func glass(_ t: StudioTarget) -> some View {
        switch t {
        case .bar:
            Section {
                Picker(L("Background"), selection: $m.draft.backdrop) {
                    Text(L("Keep current")).tag("")
                    ForEach(Backdrop.allCases.filter { $0 != .customImage }, id: \.self) { b in Text(b.name).tag(b.rawValue) }
                }
                Toggle(L("Draw a skin instead of glass"), isOn: Binding(get: { m.draft.isSkin }, set: { on in
                    m.draft.skin = on ? Skin(bar: BarStyle(fill: "#101014")) : nil
                }))
            }
        case .button, .group:
            Section {
                ColorPicker(L("Glass color"), selection: hex(\.glassColor), supportsOpacity: false)
                ColorPicker(L("Text color"), selection: hex(\.textColor), supportsOpacity: false)
                NumberRow(title: L("Glass fill"), value: $m.draft.glass, range: 0...2.5)
                NumberRow(title: L("Edge light"), value: $m.draft.edge, range: 0...2.5)
                NumberRow(title: L("Touch glow"), value: $m.draft.glow, range: 0...2.5)
                NumberRow(title: L("Corner radius"), value: $m.draft.cornerRadius, range: 0...13, format: "%.0f")
            }
        case .slider:
            Section { OptionalColorRow(title: L("Slider color"), value: optional(\.sliderColor)) }
        case .role(let k):
            Section {
                OptionalColorRow(title: L("Color"), value: Binding(get: { m.draft.roles[k]?.fill }, set: { v in
                    var p = m.draft.roles[k] ?? LayerPatch()
                    p.fill = v
                    m.draft.roles[k] = p == LayerPatch() ? nil : p
                }))
            }
        }
    }

    private func hex(_ k: WritableKeyPath<Theme, String>) -> Binding<Color> {
        Binding(get: { Color(hexString: m.draft[keyPath: k]) ?? .white }, set: { m.draft[keyPath: k] = $0.hexString })
    }

    private func optional(_ k: WritableKeyPath<Theme, String>) -> Binding<String?> {
        Binding(get: { m.draft[keyPath: k].isEmpty ? nil : m.draft[keyPath: k] }, set: { m.draft[keyPath: k] = $0 ?? "" })
    }
}

// MARK: editing from the canvas

extension StudioModel {
    func pick(_ t: StudioTarget) {
        selected = t
        part = .selection
        if case .role(let k) = t { role = k }
    }

    /// "fill:#FF453A", "text:#…", "borderColor:#…", "border:dashed", "radius:6", "glow:4", "font:mono" onto a part.
    func apply(_ payload: String, to t: StudioTarget) {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let (key, value) = (parts[0], parts[1])
        selected = t
        if key == "font" { setFont(value); return }
        if draft.isSkin { applySkin(key, value, t) } else { applyGlass(key, value, t) }
    }

    private func setFont(_ v: String) {
        if draft.isSkin {
            var s = draft.skin ?? Skin()
            var text = s.text ?? TextStyle()
            text.font = v
            s.text = text
            draft.skin = s
        } else {
            draft.fontDesign = ["mono": .monospaced, "rounded": .rounded, "serif": .serif][v] ?? .standard
        }
    }

    private func applySkin(_ key: String, _ value: String, _ t: StudioTarget) {
        func edit(_ p: inout LayerPatch) {
            switch key {
            case "fill": p.fill = value
            case "text": p.text = value
            case "borderColor": p.borderColor = value; if p.border == nil || p.border == "none" { p.border = "solid" }
            case "border": p.border = value
            case "radius": p.radius = Double(value)
            case "glow": p.glow = Double(value).flatMap { $0 > 0 ? $0 : nil }
            default: break
            }
        }
        var s = draft.skin ?? Skin()
        switch t {
        case .bar:
            var b = s.bar ?? BarStyle()
            if key == "fill" { b.fill = value } else if key == "text" || key == "borderColor" { b.patternColor = value; if b.pattern == nil { b.pattern = "grid" } }
            s.bar = b
        case .button: var p = s.button ?? LayerPatch(); edit(&p); s.button = p
        case .group: var p = s.group ?? LayerPatch(); edit(&p); s.group = p
        case .slider: if key == "fill" { draft.sliderColor = value; return }
        case .role(let k): var p = draft.roles[k] ?? LayerPatch(); edit(&p); draft.roles[k] = p; return
        }
        draft.skin = s
    }

    private func applyGlass(_ key: String, _ value: String, _ t: StudioTarget) {
        switch (t, key) {
        case (.role(let k), "fill"): var p = draft.roles[k] ?? LayerPatch(); p.fill = value; draft.roles[k] = p
        case (.slider, "fill"): draft.sliderColor = value
        case (_, "fill"): draft.glassColor = value
        case (_, "text"): draft.textColor = value
        case (_, "radius"): draft.cornerRadius = min(13, Double(value) ?? 13)
        case (_, "glow"): draft.glow = min(2.5, (Double(value) ?? 0) / 2)
        case (_, "border"), (_, "borderColor"):
            message = L("Borders are for skins. Turn on “Draw a skin instead of glass” under Info.")
        default: break
        }
    }

    /// The draft's own colors first in the palette.
    var themeColors: [String] {
        var l: [String] = []
        func add(_ s: String?) { if let s, Color(hexString: s) != nil, !l.contains(s.uppercased()) { l.append(s.uppercased()) } }
        if let s = draft.skin { [s.bar?.fill, s.button?.fill, s.button?.text, s.button?.borderColor, s.group?.fill].forEach(add) }
        [draft.glassColor, draft.textColor, draft.accent].forEach(add)
        draft.roles.values.map(\.fill).forEach(add)
        return Array(l.prefix(6))
    }

    // MARK: undo

    func undo() {
        guard let last = undoStack.popLast() else { return }
        isUndoing = true
        redoStack.append(draft)
        draft = last
        isUndoing = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        isUndoing = true
        undoStack.append(draft)
        draft = next
        isUndoing = false
    }
}
