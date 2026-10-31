import AppKit
import SwiftUI

/// Theme editor window (Theme → Theme Editor…). Every change shows on the Touch Bar right away; closing without saving
/// goes back to the saved theme. Built-in themes are saved as a copy. Themes are shared as .glasstheme files.
enum ThemeEditor {
    private static var window: NSWindow?
    private static var closeDelegate: CloseDelegate?

    static func open(_ d: AppState) {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let m = ThemeEditorModel(d)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = L("Theme Editor")
        w.contentView = NSHostingView(rootView: ThemeEditorView(m: m))
        w.isReleasedWhenClosed = false
        w.center()
        closeDelegate = CloseDelegate { m.revert(); window = nil; closeDelegate = nil }
        w.delegate = closeDelegate
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

private final class CloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ n: Notification) { onClose() }
}

final class ThemeEditorModel: ObservableObject {
    let d: AppState
    @Published var themes = ThemeStore.shared.all
    /// the theme being edited, shown live on the Touch Bar
    @Published var draft: Theme { didSet { if draft != oldValue { d.apply(draft) } } }
    /// the saved version of the draft
    @Published var saved: Theme
    @Published var message = ""
    /// value of the preview slider
    @Published var previewValue: Float = 0.6

    init(_ d: AppState) {
        self.d = d
        draft = d.theme
        saved = d.theme
    }

    var isDirty: Bool { draft != saved }

    func select(_ t: Theme) {
        draft = t
        saved = t
        message = ""
    }

    func newTheme() {
        var t = draft
        t.name = L("New Theme")
        t.id = ThemeStore.newID(t.name)
        t.author = NSFullUserName()
        t.version = 1
        saved = t
        draft = t
        message = ""
    }

    func save() {
        var t = draft
        if t.isBuiltIn {
            if t.name == saved.name { t.name = t.displayName + " " + L("Copy") }
            t.id = ThemeStore.newID(t.name)
            if t.author.isEmpty { t.author = NSFullUserName() }
        }
        do {
            try ThemeStore.shared.save(t)
            themes = ThemeStore.shared.all
            saved = t
            draft = t
            message = L("Saved")
        } catch { message = error.localizedDescription }
    }

    func delete() {
        guard !draft.isBuiltIn else { return }
        ThemeStore.shared.delete(draft.id)
        themes = ThemeStore.shared.all
        select(.classic)
    }

    func revert() { draft = saved }

    func export() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.glassTheme]
        p.nameFieldStringValue = draft.displayName + ".glasstheme"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try ThemeStore.shared.encode(draft).write(to: url, options: .atomic)
            message = L("Exported")
        } catch { message = error.localizedDescription }
    }

    func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.glassTheme, .json]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let t = try ThemeStore.shared.install(url)
            themes = ThemeStore.shared.all
            select(t)
        } catch { message = L("Could not read the theme file.") }
    }
}

struct ThemeEditorView: View {
    @ObservedObject var m: ThemeEditorModel

    var body: some View {
        HStack(spacing: 0) {
            themeList.frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                preview
                Divider()
                form
                Divider()
                actions
            }
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    // MARK: list

    private var themeList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(m.themes) { t in
                        Button { m.select(t) } label: {
                            HStack(spacing: 8) {
                                swatch(t)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.displayName).lineLimit(1)
                                    if !t.author.isEmpty { Text(t.author).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 6).fill(m.draft.id == t.id ? Color.accentColor.opacity(0.22) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            Divider()
            HStack {
                Button(L("New Theme"), action: m.newTheme)
                Spacer()
                Button(L("Import…"), action: m.importFile)
            }
            .padding(10)
        }
    }

    private func swatch(_ t: Theme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.black)
            t.shape(14).fill(t.glassTint.opacity(min(1, 0.35 * t.glass))).frame(width: 22, height: 14)
            t.shape(14).strokeBorder(t.glassTint.opacity(min(1, 0.6 * t.edge)), lineWidth: 1).frame(width: 22, height: 14)
            if let a = t.accentColor { Circle().fill(a).frame(width: 5, height: 5).offset(x: 9, y: -6) }
        }
        .frame(width: 30, height: 22)
    }

    // MARK: preview

    private var preview: some View {
        VStack(spacing: 8) {
            HStack(spacing: Metrics.spacing) {
                GlassButton(width: Metrics.escWidth, action: {}) { Text("esc") }
                GlassButton("safari", action: {})
                ButtonGroup(buttons: [.init(symbol: "chevron.left") {}, .init(symbol: "chevron.right") {}], buttonWidth: Metrics.narrowWidth)
                GlassButton(width: 150, action: {}) {
                    HStack(spacing: 6) { Image(systemName: "magnifyingglass"); Text(L("Search")); Spacer(minLength: 0) }
                }
                GlassButton("plus", highlight: .accent) {}
                GlassSlider(value: $m.previewValue, fillColor: Color(hex: 0x0A84FF)).frame(width: 110)
                ButtonGroup(buttons: [.init(symbol: "sun.max.fill") {}, .init(symbol: "speaker.wave.2.fill") {},
                                      .init(symbol: "speaker.slash.fill") {}], buttonWidth: Metrics.iconWidth)
            }
            .frame(height: Metrics.barHeight)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
            .environment(\.theme, m.draft)
            .fontDesign(m.draft.design)
            Text(L("Changes show on your Touch Bar right away. Touch the preview to try the press effect."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }

    // MARK: form

    private var form: some View {
        Form {
            if m.draft.isSkin {
                Section {
                    Text(L("This theme draws its own skin (theme.json in its package). The settings below change only its name and the parts it doesn’t set; Theme Studio will edit skins."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Info")) {
                TextField(L("Name"), text: $m.draft.name)
                TextField(L("Author"), text: $m.draft.author)
                Picker(L("Style"), selection: $m.draft.style) {
                    Text(L("Classic")).tag(Theme.Style.classic)
                    Text(L("Minimal Liquid Glass")).tag(Theme.Style.minimal)
                }
                .pickerStyle(.segmented)
                if m.draft.isBuiltIn {
                    Text(L("This is a built-in theme; saving makes a copy.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Colors")) {
                ColorPicker(L("Glass color"), selection: color(\.glassColor), supportsOpacity: false)
                ColorPicker(L("Text color"), selection: color(\.textColor), supportsOpacity: false)
                optionalColor(L("Accent color"), \.accent, default: "#0A84FF")
                optionalColor(L("Slider color"), \.sliderColor, default: "#0A84FF")
            }
            Section(L("Glass")) {
                slider(L("Glass fill"), \.glass, 0...2.5)
                slider(L("Edge light"), \.edge, 0...2.5)
                slider(L("Touch glow"), \.glow, 0...2.5)
                slider(L("Shadow"), \.shadow, 0...2)
                slider(L("Bounce"), \.bounce, 0...2)
                slider(L("Corner radius"), \.cornerRadius, 0...13, format: "%.0f")
            }
            Section(L("Text")) {
                Picker(L("Font"), selection: $m.draft.fontDesign) {
                    Text(L("Standard")).tag(Theme.FontDesign.standard)
                    Text(L("Rounded")).tag(Theme.FontDesign.rounded)
                    Text(L("Monospaced")).tag(Theme.FontDesign.monospaced)
                    Text(L("Serif")).tag(Theme.FontDesign.serif)
                }
                Picker(L("Font weight"), selection: $m.draft.fontWeight) {
                    Text(L("Regular")).tag(Theme.FontWeight.regular)
                    Text(L("Medium")).tag(Theme.FontWeight.medium)
                    Text(L("Semibold")).tag(Theme.FontWeight.semibold)
                    Text(L("Bold")).tag(Theme.FontWeight.bold)
                }
            }
            Section(L("Background")) {
                Picker(L("Background"), selection: $m.draft.backdrop) {
                    Text(L("Keep current")).tag("")
                    ForEach(Backdrop.allCases.filter { $0 != .customImage }, id: \.self) { b in Text(b.name).tag(b.rawValue) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func color(_ k: WritableKeyPath<Theme, String>) -> Binding<Color> {
        Binding(get: { Color(hexString: m.draft[keyPath: k]) ?? .white }, set: { m.draft[keyPath: k] = $0.hexString })
    }

    private func optionalColor(_ title: String, _ k: WritableKeyPath<Theme, String>, default value: String) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { !m.draft[keyPath: k].isEmpty }, set: { m.draft[keyPath: k] = $0 ? value : "" }))
            Spacer()
            if !m.draft[keyPath: k].isEmpty { ColorPicker("", selection: color(k), supportsOpacity: false).labelsHidden() }
        }
    }

    private func slider(_ title: String, _ k: WritableKeyPath<Theme, Double>, _ range: ClosedRange<Double>, format: String = "%.2f") -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { m.draft[keyPath: k] }, set: { m.draft[keyPath: k] = $0 }), in: range)
            Text(String(format: format, m.draft[keyPath: k])).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: actions

    private var actions: some View {
        HStack {
            Button(L("Delete"), role: .destructive, action: m.delete).disabled(m.draft.isBuiltIn)
            Text(m.message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L("Revert"), action: m.revert).disabled(!m.isDirty)
            Button(L("Export…"), action: m.export)
            Button(L("Save"), action: m.save).keyboardShortcut("s").disabled(!m.isDirty && !m.draft.isBuiltIn)
        }
        .padding(12)
    }
}
