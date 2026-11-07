import AppKit
import SwiftUI

// Layout Studio's canvas, like Theme Studio's: the whole bar at its real width (esc, the app's icon, the layout,
// the Control Strip) drawn with your theme on an AppState of its own. A clear layer on top catches clicks, drags
// and drops, so no shortcut on the canvas ever runs.

struct LayoutCellsKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct LayoutStudioCanvas: View {
    @ObservedObject var m: LayoutEditorModel
    @ObservedObject var d: AppState
    @StateObject private var drag = CanvasDrag()

    var body: some View {
        let t = d.theme
        let p = m.previewState
        GeometryReader { g in
            let scale = m.zoom > 0 ? m.zoom : min(1, g.size.width / p.width)
            ScrollView(.horizontal, showsIndicators: m.zoom > 0) {
                bar(p)
                    .frame(width: p.width, height: Metrics.barHeight)
                    .coordinateSpace(name: "layoutCanvas")
                    .background { if let b = t.skin?.bar { SkinBarBackground(style: b, theme: t) } else { Color.black } }
                    .overlay { if let b = t.skin?.bar { SkinBarOverlay(style: b).allowsHitTesting(false) } }
                    .environment(\.theme, t)
                    .font(t.font(14))
                    .textCase(t.letterCase)
                    .overlayPreferenceValue(LayoutCellsKey.self) { frames in catcher(frames) }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: p.width * scale, height: Metrics.barHeight * scale, alignment: .topLeading)
            }
            .scrollDisabled(m.zoom == 0)
        }
        .frame(height: Metrics.barHeight * (m.zoom > 0 ? m.zoom : 1) + (m.zoom > 0 ? 12 : 0))
    }

    private func bar(_ p: AppState) -> some View {
        HStack(spacing: Metrics.spacing) {
            if p.showsEsc { GlassButton(width: Metrics.escWidth, action: {}) { Text("esc").kerning(0.3) } }
            GlassButton(width: Metrics.iconWidth, action: {}) {
                if let icon = p.frontIcon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) } else { Icon("app") }
            }
            HStack(spacing: Metrics.spacing) {
                ForEach(Array(m.draft.items.enumerated()), id: \.offset) { i, item in
                    cell(item)
                        .opacity(drag.index == i ? 0.35 : 1)
                        .background(GeometryReader { g in Color.clear.preference(key: LayoutCellsKey.self, value: [i: g.frame(in: .named("layoutCanvas"))]) })
                }
                if m.draft.items.isEmpty {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .overlay(Text(L("Drag items here from the library")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)))
                        .frame(maxWidth: .infinity).frame(height: Metrics.buttonHeight)
                }
                if !m.draft.items.contains(where: { $0.type == "space" }) { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity)
            CollapsedControlStrip(d: p)
        }
        .padding(.horizontal, 3)
    }

    @ViewBuilder private func cell(_ item: LayoutItem) -> some View {
        if item.type == "space" {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)))
                .frame(minWidth: 40, maxWidth: .infinity).frame(height: Metrics.buttonHeight)
        } else {
            HStack(spacing: Metrics.spacing) { LayoutBar(d: m.previewState, layout: single(item)) }
        }
    }

    private func single(_ item: LayoutItem) -> BarLayout {
        var l = m.draft
        l.items = [item]
        return l
    }

    /// Click selects, press and drag moves, library items and role chips drop where the pointer is.
    private func catcher(_ frames: [Int: CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            if let i = m.selection, let f = frames[i], drag.index == nil {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: f.width + 6, height: f.height + 6).offset(x: f.minX - 3, y: f.minY - 3)
            }
            if let h = drag.hover, let f = frames[h], h != m.selection, drag.index == nil {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: f.width + 4, height: f.height + 4).offset(x: f.minX - 2, y: f.minY - 2)
            }
            if let x = drag.markerX {
                Capsule().fill(Color.accentColor).frame(width: 3, height: Metrics.buttonHeight + 4).offset(x: x - 1.5, y: 0)
            }
            if let i = drag.index, let f = frames[i] {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: f.width, height: f.height).offset(x: f.minX + drag.dx, y: f.minY)
            }
            Rectangle().fill(Color.white.opacity(0.001))
                .onContinuousHover { phase in
                    if case .active(let p) = phase { drag.hover = item(at: p, frames) } else { drag.hover = nil }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { e in
                        if drag.start == nil { drag.start = item(at: e.startLocation, frames) ?? -1 }
                        guard let s = drag.start, s >= 0, abs(e.translation.width) > 4 || drag.index != nil else { return }
                        drag.index = s
                        drag.dx = e.translation.width
                        drag.markerX = markerX(insertion(e.location.x, frames, excluding: s), frames)
                    }
                    .onEnded { e in
                        if let s = drag.index {
                            m.move(from: s, to: insertion(e.location.x, frames, excluding: s))
                        } else {
                            m.selection = item(at: e.location, frames)
                        }
                        drag.reset()
                    })
                .dropDestination(for: String.self) { items, p in
                    drag.markerX = nil
                    guard let s = items.first else { return false }
                    if s.hasPrefix("role:") {
                        guard let i = item(at: p, frames) else { return false }
                        m.setRole(String(s.dropFirst(5)), at: i)
                    } else if s.hasPrefix("new:"), let i = Int(s.dropFirst(4)), LayoutLibrary.entries.indices.contains(i) {
                        m.insert(LayoutLibrary.entries[i].2, at: insertion(p.x, frames, excluding: nil))
                    }
                    return true
                } isTargeted: { if !$0 { drag.markerX = nil } }
        }
    }

    private func item(at p: CGPoint, _ frames: [Int: CGRect]) -> Int? {
        frames.first { $0.value.insetBy(dx: -2, dy: -4).contains(p) }?.key
    }

    /// Where an item dropped at x goes: before the first item whose middle is right of x.
    private func insertion(_ x: CGFloat, _ frames: [Int: CGRect], excluding: Int?) -> Int {
        let sorted = frames.sorted { $0.key < $1.key }
        let before = sorted.filter { $0.key != excluding && $0.value.midX < x }.count
        guard let ex = excluding else { return before }
        // move(from:to:) takes the index in the list that still contains the moved item
        return before >= ex ? before + 1 : before
    }

    private func markerX(_ index: Int, _ frames: [Int: CGRect]) -> CGFloat? {
        let sorted = frames.sorted { $0.key < $1.key }.map(\.value)
        guard !sorted.isEmpty else { return nil }
        if index <= 0 { return sorted[0].minX - Metrics.spacing / 2 }
        if index >= sorted.count { return sorted[sorted.count - 1].maxX + Metrics.spacing / 2 }
        return (sorted[index - 1].maxX + sorted[index].minX) / 2
    }
}

private final class CanvasDrag: ObservableObject {
    @Published var index: Int?
    @Published var dx: CGFloat = 0
    @Published var markerX: CGFloat?
    @Published var hover: Int?
    var start: Int?

    func reset() { index = nil; dx = 0; markerX = nil; start = nil }
}

/// Role chips: drop one on a button, or click to give it to the selection.
struct LayoutRoleChips: View {
    @ObservedObject var m: LayoutEditorModel

    var body: some View {
        HStack(spacing: 6) {
            Text(L("Roles:")).font(.caption).foregroundStyle(.secondary)
            ForEach([""] + Role.allKeys, id: \.self) { k in
                Text(k.isEmpty ? L("None") : Role.title(k)).font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(k.isEmpty ? Color.secondary.opacity(0.15) : (Theme.minimal.glassColor(Role.named(k) ?? .active) ?? .gray).opacity(0.5)))
                    .contentShape(Capsule())
                    .onTapGesture { if let i = m.selection { m.setRole(k, at: i) } }
                    .draggable("role:" + k)
            }
            Spacer()
        }
    }
}

// MARK: built-in bars as starting points

/// GlassBar's own bars written as layouts, to start a layout from. Buttons that follow the app's state
/// (Safari's tabs, the playing track) become plain shortcuts here.
enum BuiltInLayouts {
    static func items(for bundleID: String) -> [LayoutItem] {
        func b(_ icon: String, _ shortcut: String, role: String? = nil) -> LayoutItem { LayoutItem(icon: icon, role: role, action: LayoutAction(shortcut: shortcut)) }
        func t(_ label: String, _ shortcut: String, role: String? = nil) -> LayoutItem { LayoutItem(label: label, role: role, action: LayoutAction(shortcut: shortcut)) }
        func g(_ items: [LayoutItem]) -> LayoutItem { LayoutItem(type: "group", items: items) }
        let space = LayoutItem(type: "space")
        switch bundleID {
        case "com.apple.finder":
            return [g([b("chevron.left", "cmd+["), b("chevron.right", "cmd+]")]), g([b("square.grid.2x2", "cmd+1"), b("list.bullet", "cmd+2"), b("rectangle.split.3x1", "cmd+3")]),
                    b("eye", "space"), b("folder.badge.plus", "cmd+shift+n"), space, b("magnifyingglass", "cmd+f"), b("trash", "cmd+delete")]
        case "com.apple.Safari":
            return [g([b("chevron.left", "cmd+["), b("chevron.right", "cmd+]")]), b("arrow.clockwise", "cmd+r"),
                    LayoutItem(label: L("Search or enter website"), icon: "magnifyingglass", width: 240, action: LayoutAction(shortcut: "cmd+l")),
                    b("plus", "cmd+t", role: "accent"), b("square.on.square", "cmd+shift+\\"), b("sidebar.left", "cmd+shift+l")]
        case "com.apple.mail":
            return [b("square.and.pencil", "cmd+n"), g([b("arrowshape.turn.up.left", "cmd+r"), b("arrowshape.turn.up.left.2", "cmd+shift+r"),
                    b("arrowshape.turn.up.right", "cmd+shift+f")]), b("archivebox", "ctrl+cmd+a"), b("trash", "delete"), b("flag", "cmd+shift+l"), space]
        case "com.apple.Notes":
            return [b("square.and.pencil", "cmd+n"), b("checklist", "cmd+shift+l"), b("tablecells", "alt+cmd+t"),
                    g([b("bold", "cmd+b"), b("italic", "cmd+i"), b("underline", "cmd+u")]), space]
        case "com.apple.calculator":
            return [space, g([t("÷", "/", role: "operator"), t("×", "shift+8", role: "operator"), t("−", "-", role: "operator"),
                              t("+", "shift+=", role: "operator"), t("=", "return", role: "operator")])]
        case NowPlaying.music, NowPlaying.spotify:
            return [g([b("backward.fill", "cmd+left"), b("playpause.fill", "space"), b("forward.fill", "cmd+right")]),
                    LayoutItem(type: "widget", widget: "nowPlaying"), space, g([b("speaker.minus", "cmd+down"), b("speaker.plus", "cmd+up")])]
        case "com.apple.iCal":
            return [g([b("chevron.left", "cmd+left"), b("chevron.right", "cmd+right")]), t(L("Today"), "cmd+t"),
                    g([t(L("Day"), "cmd+1"), t(L("Week"), "cmd+2"), t(L("Month"), "cmd+3")]), space, b("plus", "cmd+n")]
        case "com.apple.Preview":
            return [g([b("minus.magnifyingglass", "cmd+-"), b("plus.magnifyingglass", "cmd+=")]), g([b("rotate.left", "cmd+l"), b("rotate.right", "cmd+r")]),
                    b("pencil.tip.crop.circle", "cmd+shift+a"), space]
        case "com.apple.MobileSMS":
            return [b("square.and.pencil", "cmd+n"), b("face.smiling", "ctrl+cmd+space"), space]
        case "com.apple.TextEdit":
            return [g([b("bold", "cmd+b"), b("italic", "cmd+i"), b("underline", "cmd+u")]),
                    g([b("text.alignleft", "cmd+shift+["), b("text.aligncenter", "cmd+shift+\\"), b("text.alignright", "cmd+shift+]")]), space]
        default:
            return [b("face.smiling", "ctrl+cmd+space"), space]
        }
    }
}

// MARK: model

extension LayoutEditorModel {
    func setRole(_ k: String, at i: Int) {
        guard draft.items.indices.contains(i) else { return }
        draft.items[i].role = k.isEmpty ? nil : k
        selection = i
    }

    /// The layout for an app: the saved one, or a new draft (empty, or a copy of GlassBar's built-in bar).
    func open(app id: String, fromBuiltIn: Bool) {
        if fromBuiltIn && draft.apps.contains(id) {
            draft.items = BuiltInLayouts.items(for: id)
            selection = nil
            message = L("A copy of the built-in bar. Buttons that follow the app’s state became plain shortcuts.")
            return
        }
        if !fromBuiltIn, let l = layouts.first(where: { $0.apps.contains(id) }) { select(l); return }
        var l = Self.blank()
        l.apps = [id]
        l.name = LayoutList.appName(id)
        l.id = ThemeStore.newID(l.name)
        if fromBuiltIn { l.items = BuiltInLayouts.items(for: id) }
        draft = l
        saved = nil
        selection = nil
        undoStack = []
        redoStack = []
        message = fromBuiltIn ? L("A copy of the built-in bar. Buttons that follow the app’s state became plain shortcuts.") : ""
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        isUndoing = true
        redoStack.append(draft)
        draft = last
        isUndoing = false
        selection = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        isUndoing = true
        undoStack.append(draft)
        draft = next
        isUndoing = false
        selection = nil
    }
}
