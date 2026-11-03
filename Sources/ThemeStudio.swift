import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Theme Studio, a page in the Hub: edits glass themes and skins without writing JSON. The draft shows on the
// Touch Bar while you edit; leaving the Hub without saving puts the saved theme back.

final class StudioModel: ObservableObject {
    enum Part: String, CaseIterable {
        case info, glass, bar, buttons, roles, text, icons, effects, assets

        var name: String {
            switch self {
            case .info: L("Info")
            case .glass: L("Glass")
            case .bar: L("Bar")
            case .buttons: L("Buttons")
            case .roles: L("Roles")
            case .text: L("Text")
            case .icons: L("Icons")
            case .effects: L("Effects")
            case .assets: L("Assets")
            }
        }
    }

    let d: AppState
    private let original: Theme
    @Published var themes = ThemeStore.shared.all
    @Published var draft: Theme { didSet { if draft != oldValue { d.apply(draft) } } }
    @Published var saved: Theme
    @Published var message = ""
    @Published var part = Part.info
    @Published var role = "active"
    @Published var previewValue: Float = 0.6

    init(_ d: AppState) {
        self.d = d
        original = d.theme
        draft = d.theme
        saved = d.theme
        // screenshot testing: -studioPart buttons
        if let p = UserDefaults.standard.string(forKey: "studioPart").flatMap(Part.init(rawValue:)), parts.contains(p) { part = p }
    }

    var isDirty: Bool { draft != saved }
    var parts: [Part] { draft.isSkin ? Part.allCases.filter { $0 != .glass } : [.info, .glass, .roles, .text] }

    /// Called when the Hub closes: unsaved changes don't stay on the bar.
    func close() {
        guard isDirty || ThemeStore.shared.theme(id: draft.id) == nil else { return }
        d.apply(ThemeStore.shared.theme(id: saved.id) ?? original)
    }

    func select(_ t: Theme) {
        draft = t
        saved = t
        message = ""
        if !parts.contains(part) { part = .info }
    }

    func newTheme(skin: Bool) {
        var t = skin ? Theme(id: "", name: L("New Skin"), skin: Skin(
            bar: BarStyle(fill: "#101014"),
            button: LayerPatch(fill: "#26262C", text: "#F2F2F2", border: "solid", borderWidth: 1, borderColor: "#3A3A44", radius: 6),
            pressed: LayerPatch(fill: "#3A3A44"),
            text: TextStyle(font: "system"))) : Theme(id: "", name: L("New Theme"))
        t.id = ThemeStore.newID(t.name)
        t.author = NSFullUserName()
        saved = t
        draft = t
        message = ""
        part = .info
    }

    func duplicate() {
        var t = draft
        t.name = draft.displayName + " " + L("Copy")
        t.id = ThemeStore.newID(t.name)
        t.version = 1
        if t.author.isEmpty { t.author = NSFullUserName() }
        do { select(try ThemeStore.shared.save(t)); themes = ThemeStore.shared.all; message = L("Saved") } catch { message = error.localizedDescription }
    }

    func save() {
        var t = draft
        if t.isBuiltIn {
            if t.name == saved.name { t.name = t.displayName + " " + L("Copy") }
            t.id = ThemeStore.newID(t.name)
            if t.author.isEmpty { t.author = NSFullUserName() }
        } else if isDirty {
            t.version += 1
        }
        do {
            t = try ThemeStore.shared.save(t)
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
        do { try ThemeStore.shared.export(draft, to: url); message = L("Exported") } catch { message = error.localizedDescription }
    }

    func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.glassTheme, .json]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        install(url)
    }

    func install(_ url: URL) {
        do { select(try ThemeStore.shared.install(url)); themes = ThemeStore.shared.all } catch { message = L("Could not read the theme file.") }
    }

    // MARK: assets

    /// Files in the theme's package, theme.json and the preview left out.
    var assets: [String] {
        guard let base = draft.baseURL else { return [] }
        let l = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return l.filter { !$0.hasPrefix(".") && $0 != "theme.json" && $0 != "preview.png" }.sorted()
    }

    func assets(_ extensions: Set<String>) -> [String] { assets.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) } }

    /// Fonts, images and sounds are copied into the package; a single-file theme becomes a package first.
    func addAssets() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.font, .image, .audio]
        p.allowsMultipleSelection = true
        p.message = L("Fonts, images and sounds are copied into the theme.")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, !p.urls.isEmpty else { return }
        if draft.isBuiltIn || draft.baseURL == nil || isDirty { save() }
        do {
            if draft.baseURL == nil {
                let t = try ThemeStore.shared.makePackage(draft)
                saved = t
                draft = t
            }
            guard let base = draft.baseURL else { return }
            for u in p.urls {
                let to = base.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: u, to: to)
            }
            objectWillChange.send()
            message = String(format: L("%d files added"), p.urls.count)
        } catch { message = error.localizedDescription }
    }

    func removeAsset(_ name: String) {
        guard let base = draft.baseURL else { return }
        try? FileManager.default.trashItem(at: base.appendingPathComponent(name), resultingItemURL: nil)
        objectWillChange.send()
    }

    // MARK: bindings into the skin

    func skin<T>(_ k: WritableKeyPath<Skin, T?>, empty: T) -> Binding<T> where T: Equatable {
        Binding(get: { self.draft.skin?[keyPath: k] ?? empty }, set: { v in
            var s = self.draft.skin ?? Skin()
            s[keyPath: k] = v == empty ? nil : v
            self.draft.skin = s
        })
    }

    func roleLayer(_ key: String) -> Binding<LayerPatch> {
        Binding(get: { self.draft.roles[key] ?? LayerPatch() }, set: { self.draft.roles[key] = $0 == LayerPatch() ? nil : $0 })
    }
}

extension ThemeStore {
    /// Turns a saved single-file theme into a package folder so it can carry fonts, images and sounds.
    func makePackage(_ t: Theme) throws -> Theme {
        let fm = FileManager.default
        if let old = locations[t.id] { try? fm.removeItem(at: old) }
        let to = folder.appendingPathComponent(t.id + ".glasstheme")
        try? fm.removeItem(at: to)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        var p = t
        p.baseURL = to
        try encode(p).write(to: to.appendingPathComponent("theme.json"), options: .atomic)
        reload()
        return p
    }
}

// MARK: views

struct ThemeStudioView: View {
    @ObservedObject var m: StudioModel

    var body: some View {
        HStack(spacing: 0) {
            StudioThemeList(m: m).frame(width: 200)
            Divider()
            VStack(spacing: 0) {
                StudioPreview(m: m)
                Divider()
                Picker("", selection: $m.part) {
                    ForEach(m.parts, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14).padding(.vertical, 8)
                StudioPartForm(m: m)
                Divider()
                actions
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension == "glasstheme" || url.pathExtension == "json" else { return }
                    DispatchQueue.main.async { m.install(url) }
                }
            }
            return true
        }
    }

    private var actions: some View {
        HStack {
            Button(L("Delete"), role: .destructive, action: m.delete).disabled(m.draft.isBuiltIn)
            Text(m.message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L("Revert"), action: m.revert).disabled(!m.isDirty)
            Button(L("Duplicate"), action: m.duplicate)
            Button(L("Export…"), action: m.export)
            Button(L("Save"), action: m.save).keyboardShortcut("s").disabled(!m.isDirty && !m.draft.isBuiltIn)
        }
        .padding(12)
    }
}

private struct StudioThemeList: View {
    @ObservedObject var m: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(m.themes) { t in
                        Button { m.select(t) } label: {
                            HStack(spacing: 8) {
                                ThemeSwatch(t: t).frame(width: 30, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.displayName).lineLimit(1)
                                    Text(t.isSkin ? L("Skin") : L("Glass")).font(.caption).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 6) {
                Menu(L("New")) {
                    Button(L("Glass Theme")) { m.newTheme(skin: false) }
                    Button(L("Skin")) { m.newTheme(skin: true) }
                }
                Button(L("Import…"), action: m.importFile)
            }
            .padding(10)
        }
    }
}

struct ThemeSwatch: View {
    let t: Theme

    var body: some View {
        if t.isSkin {
            let l = t.layer(nil), shape = RoundedRectangle(cornerRadius: min(l.radius, 7))
            let dot = t.layer(.operatorKey)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(t.skin?.bar?.fill.flatMap { Color(hexString: $0) } ?? .black)
                if let f = l.fill { shape.fill(f).frame(width: 22, height: 14) }
                shape.strokeBorder(l.border == "none" ? .clear : l.borderColor, lineWidth: 1).frame(width: 22, height: 14)
                Circle().fill(dot.fill ?? dot.text).frame(width: 5, height: 5).offset(x: 9, y: -6)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.black)
                t.shape(14).fill(t.glassTint.opacity(min(1, 0.35 * t.glass))).frame(width: 22, height: 14)
                t.shape(14).strokeBorder(t.glassTint.opacity(min(1, 0.6 * t.edge)), lineWidth: 1).frame(width: 22, height: 14)
                if let a = t.accentColor { Circle().fill(a).frame(width: 5, height: 5).offset(x: 9, y: -6) }
            }
        }
    }
}

/// A piece of a bar drawn with the draft, plus every button state side by side.
private struct StudioPreview: View {
    @ObservedObject var m: StudioModel

    var body: some View {
        let t = m.draft
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.spacing) {
                    GlassButton(width: Metrics.escWidth, action: {}) { Text("esc") }
                    GlassButton("safari", action: {})
                    ButtonGroup(buttons: [.init(symbol: "chevron.left") {}, .init(symbol: "chevron.right") {}], buttonWidth: Metrics.narrowWidth)
                    GlassButton(width: 150, action: {}) {
                        HStack(spacing: 6) { Icon("magnifyingglass"); Text(L("Search")); Spacer(minLength: 0) }
                    }
                    GlassButton("plus", highlight: .accent) {}
                    GlassButton(width: nil, highlight: .primary, action: {}) { Text(L("Done")) }
                    GlassSlider(value: $m.previewValue, fillColor: Color(hex: 0x0A84FF)).frame(width: 110)
                    ButtonGroup(buttons: [.init(symbol: "sun.max.fill") {}, .init(symbol: "speaker.wave.2.fill") {},
                                          .init(symbol: "speaker.slash.fill") {}], buttonWidth: Metrics.iconWidth)
                }
                .frame(height: Metrics.barHeight)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background { bar(t) }
                .overlay { if let b = t.skin?.bar { SkinBarOverlay(style: b).allowsHitTesting(false) } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .environment(\.theme, t)
                .font(t.font(14))
                .textCase(t.letterCase)
            }
            HStack(spacing: 14) {
                state(L("Normal"), nil, pressed: false)
                state(L("Pressed"), nil, pressed: true)
                state(L("Active"), .active, pressed: false)
                state(L("Primary"), .primary, pressed: false)
                state(L("Disabled"), nil, pressed: false).opacity(0.4)
            }
            Text(L("Changes show on your Touch Bar right away. Touch the preview to try the press effect."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func bar(_ t: Theme) -> some View {
        if let b = t.skin?.bar { SkinBarBackground(style: b, theme: t) } else { Color.black }
    }

    private func state(_ title: String, _ role: Role?, pressed: Bool) -> some View {
        let t = m.draft
        return VStack(spacing: 4) {
            Group {
                if t.isSkin {
                    let l = t.layer(role, pressed: pressed)
                    Text(l.border == "ascii" ? "\(l.opening)Aa\(l.closing)" : "Aa")
                        .font(t.font(13)).foregroundStyle(l.text)
                        .frame(width: 64, height: Metrics.buttonHeight)
                        .background(SkinBackground(role: role, isPressed: pressed))
                } else {
                    GlassButton(width: 64, highlight: role, action: {}) { Text("Aa") }
                        .scaleEffect(pressed ? 0.94 : 1)
                }
            }
            .frame(height: Metrics.barHeight)
            .padding(4)
            .background { bar(t).clipShape(RoundedRectangle(cornerRadius: 6)) }
            .environment(\.theme, t)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct StudioPartForm: View {
    @ObservedObject var m: StudioModel

    var body: some View {
        Form {
            switch m.part {
            case .info: info
            case .glass: glass
            case .bar: bar
            case .buttons: buttons
            case .roles: roles
            case .text: text
            case .icons: StudioIcons(m: m)
            case .effects: effects
            case .assets: assets
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var info: some View {
        Section {
            TextField(L("Name"), text: $m.draft.name)
            TextField(L("Author"), text: $m.draft.author)
            LabeledContent(L("Version"), value: "\(m.draft.version)")
            Toggle(L("Draw a skin instead of glass"), isOn: Binding(get: { m.draft.isSkin }, set: { on in
                m.draft.skin = on ? Skin(bar: BarStyle(fill: "#101014"),
                                         button: LayerPatch(fill: "#26262C", text: m.draft.textColor, border: "solid", borderColor: "#3A3A44", radius: 6))
                                  : nil
            }))
            if m.draft.isBuiltIn {
                Text(L("This is a built-in theme; saving makes a copy.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        Section(L("Background")) {
            Picker(L("Background"), selection: $m.draft.backdrop) {
                Text(L("Keep current")).tag("")
                ForEach(Backdrop.allCases.filter { $0 != .customImage }, id: \.self) { b in Text(b.name).tag(b.rawValue) }
            }
        }
    }

    @ViewBuilder private var glass: some View {
        Section {
            Picker(L("Style"), selection: $m.draft.style) {
                Text(L("Classic")).tag(Theme.Style.classic)
                Text(L("Minimal Liquid Glass")).tag(Theme.Style.minimal)
            }
            .pickerStyle(.segmented)
        }
        Section(L("Colors")) {
            ColorPicker(L("Glass color"), selection: hex(\.glassColor), supportsOpacity: false)
            ColorPicker(L("Text color"), selection: hex(\.textColor), supportsOpacity: false)
            OptionalColorRow(title: L("Accent color"), value: optionalHex(\.accent))
            OptionalColorRow(title: L("Slider color"), value: optionalHex(\.sliderColor))
        }
        Section(L("Glass")) {
            NumberRow(title: L("Glass fill"), value: $m.draft.glass, range: 0...2.5)
            NumberRow(title: L("Edge light"), value: $m.draft.edge, range: 0...2.5)
            NumberRow(title: L("Touch glow"), value: $m.draft.glow, range: 0...2.5)
            NumberRow(title: L("Shadow"), value: $m.draft.shadow, range: 0...2)
            NumberRow(title: L("Bounce"), value: $m.draft.bounce, range: 0...2)
            NumberRow(title: L("Corner radius"), value: $m.draft.cornerRadius, range: 0...13, format: "%.0f")
        }
    }

    @ViewBuilder private var bar: some View {
        let b = m.skin(\.bar, empty: BarStyle())
        Section(L("Bar")) {
            OptionalColorRow(title: L("Color"), value: b.fill)
            OptionalColorRow(title: L("Gradient to"), value: b.fill2)
            Picker(L("Pattern"), selection: b.pattern) {
                Text(L("None")).tag(String?.none)
                Text(L("Stars")).tag(String?.some("stars"))
                Text(L("Grid")).tag(String?.some("grid"))
            }
            if b.wrappedValue.pattern != nil { OptionalColorRow(title: L("Pattern color"), value: b.patternColor) }
            Picker(L("Overlay"), selection: b.overlay) {
                Text(L("None")).tag(String?.none)
                Text(L("Scanlines")).tag(String?.some("scanlines"))
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Section(L("Button")) { LayerEditor(p: m.skin(\.button, empty: LayerPatch())) }
        Section(L("Pressed")) { LayerEditor(p: m.skin(\.pressed, empty: LayerPatch())) }
        Section(L("Button group")) { LayerEditor(p: m.skin(\.group, empty: LayerPatch())) }
    }

    @ViewBuilder private var roles: some View {
        Section {
            Picker(L("Role"), selection: $m.role) {
                ForEach(Role.allKeys, id: \.self) { Text(Role.title($0)).tag($0) }
            }
            Text(Role.help(m.role)).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            if m.draft.isSkin {
                LayerEditor(p: m.roleLayer(m.role))
            } else {
                OptionalColorRow(title: L("Color"), value: Binding(get: { m.draft.roles[m.role]?.fill }, set: { v in
                    var p = m.draft.roles[m.role] ?? LayerPatch()
                    p.fill = v
                    m.draft.roles[m.role] = p == LayerPatch() ? nil : p
                }))
            }
        }
    }

    @ViewBuilder private var text: some View {
        if m.draft.isSkin {
            let t = m.skin(\.text, empty: TextStyle())
            Section(L("Text")) {
                Picker(L("Font"), selection: t.font) {
                    Text(L("Standard")).tag(String?.none)
                    Text(L("System")).tag(String?.some("system"))
                    Text(L("Monospaced")).tag(String?.some("mono"))
                    Text(L("Rounded")).tag(String?.some("rounded"))
                    Text(L("Serif")).tag(String?.some("serif"))
                    ForEach(m.assets(["ttf", "otf"]), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                OptionalNumberRow(title: L("Size"), value: t.scale, range: 0.5...2, initial: 1)
                Picker(L("Font weight"), selection: t.weight) {
                    Text(L("Theme default")).tag(String?.none)
                    ForEach(["regular", "medium", "semibold", "bold", "heavy"], id: \.self) { Text(L($0.capitalized)).tag(String?.some($0)) }
                }
                Picker(L("Letters"), selection: t.letterCase) {
                    Text(L("As written")).tag(String?.none)
                    Text(L("UPPERCASE")).tag(String?.some("upper"))
                    Text(L("lowercase")).tag(String?.some("lower"))
                }
                OptionalNumberRow(title: L("Letter spacing"), value: t.tracking, range: -2...6, initial: 1)
            }
        } else {
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
        }
    }

    @ViewBuilder private var effects: some View {
        Section(L("Press effect")) {
            Picker(L("Press effect"), selection: m.skin(\.press, empty: "")) {
                Text(L("Theme default")).tag("")
                Text(L("Liquid")).tag("liquid")
                Text(L("Pop")).tag("pop")
                Text(L("Shake")).tag("shake")
                Text(L("Wobble")).tag("wobble")
                Text(L("None")).tag("none")
            }
        }
        Section(L("Sounds")) {
            let sounds = m.skin(\.sounds, empty: [:])
            Picker(L("Tap"), selection: Binding(get: { sounds.wrappedValue["tap"] ?? "" }, set: { v in
                var s = sounds.wrappedValue
                s["tap"] = v.isEmpty ? nil : v
                sounds.wrappedValue = s
            })) {
                Text(L("None")).tag("")
                Text(L("Click")).tag("click")
                Text(L("Blip")).tag("blip")
                Text(L("Tick")).tag("tick")
                ForEach(m.assets(["wav", "aif", "aiff", "mp3", "m4a", "caf"]), id: \.self) { Text($0).tag($0) }
            }
            Text(L("Sounds play only when Play Theme Sounds is on.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var assets: some View {
        Section {
            if m.assets.isEmpty {
                Text(L("No files yet. Add a font, images for the icon map or a tap sound.")).foregroundStyle(.secondary)
            }
            ForEach(m.assets, id: \.self) { a in
                HStack {
                    Image(systemName: icon(a)).frame(width: 20)
                    Text(a)
                    Spacer()
                    Button(L("Remove")) { m.removeAsset(a) }.buttonStyle(.borderless)
                }
            }
            Button(L("Add Files…"), action: m.addAssets)
        }
    }

    private func icon(_ file: String) -> String {
        switch (file as NSString).pathExtension.lowercased() {
        case "ttf", "otf": "textformat"
        case "png", "jpg", "jpeg", "gif", "pdf", "tiff": "photo"
        default: "speaker.wave.2"
        }
    }

    private func hex(_ k: WritableKeyPath<Theme, String>) -> Binding<Color> {
        Binding(get: { Color(hexString: m.draft[keyPath: k]) ?? .white }, set: { m.draft[keyPath: k] = $0.hexString })
    }

    private func optionalHex(_ k: WritableKeyPath<Theme, String>) -> Binding<String?> {
        Binding(get: { m.draft[keyPath: k].isEmpty ? nil : m.draft[keyPath: k] }, set: { m.draft[keyPath: k] = $0 ?? "" })
    }
}

/// Apple symbol → text or an image from the package.
private struct StudioIcons: View {
    @ObservedObject var m: StudioModel
    @StateObject private var field = NewIconField()

    var body: some View {
        let icons = m.skin(\.icons, empty: [:])
        Section {
            ForEach(icons.wrappedValue.keys.sorted(), id: \.self) { k in
                HStack {
                    Image(systemName: k).frame(width: 24)
                    Text(k).foregroundStyle(.secondary).frame(width: 170, alignment: .leading).lineLimit(1)
                    TextField("", text: Binding(get: { icons.wrappedValue[k] ?? "" }, set: { v in icons.wrappedValue[k] = v }))
                    Menu(L("Image")) {
                        ForEach(m.assets(["png", "jpg", "jpeg", "gif", "pdf", "tiff"]), id: \.self) { a in
                            Button(a) { icons.wrappedValue[k] = "image:" + a }
                        }
                        if m.assets(["png", "jpg", "jpeg", "gif", "pdf", "tiff"]).isEmpty { Text(L("Add images under Assets")) }
                    }
                    .fixedSize()
                    Button { icons.wrappedValue[k] = nil } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
        }
        Section(L("Add")) {
            HStack {
                TextField(L("Symbol"), text: $field.symbol, prompt: Text("chevron.left"))
                Image(systemName: field.symbol.isEmpty ? "questionmark.square.dashed" : field.symbol).frame(width: 24)
                TextField(L("Shows"), text: $field.value, prompt: Text("<"))
                Button(L("Add")) {
                    icons.wrappedValue[field.symbol] = field.value
                    field.symbol = ""
                    field.value = ""
                }
                .disabled(field.symbol.isEmpty || field.value.isEmpty)
            }
            Menu(L("Common symbols")) {
                ForEach(CommonSymbols.list, id: \.self) { s in Button { field.symbol = s } label: { Label(s, systemImage: s) } }
            }
        }
    }

}

enum CommonSymbols {
    static let list = ["chevron.left", "chevron.right", "magnifyingglass", "plus", "xmark", "sun.max.fill", "speaker.wave.2.fill",
                         "speaker.slash.fill", "playpause.fill", "play.fill", "pause.fill", "forward.fill", "backward.fill",
                         "safari", "square.and.arrow.up", "star", "trash", "arrow.clockwise", "circle", "mic.fill"]
}

private final class NewIconField: ObservableObject {
    @Published var symbol = ""
    @Published var value = ""
}

/// Every field of a layer; a field left off is taken from the layer below (the button, or the theme).
struct LayerEditor: View {
    @Binding var p: LayerPatch

    var body: some View {
        Group {
            OptionalColorRow(title: L("Fill"), value: $p.fill)
            OptionalColorRow(title: L("Gradient to"), value: $p.fill2)
            OptionalColorRow(title: L("Text"), value: $p.text)
            Picker(L("Border"), selection: $p.border) {
                Text(L("Inherit")).tag(String?.none)
                Text(L("None")).tag(String?.some("none"))
                Text(L("Solid")).tag(String?.some("solid"))
                Text(L("Dashed")).tag(String?.some("dashed"))
                Text(L("Pixel")).tag(String?.some("pixel"))
                Text(L("ASCII brackets")).tag(String?.some("ascii"))
                Text(L("Hand-drawn")).tag(String?.some("sketch"))
            }
            if p.border == "ascii" {
                TextField(L("Brackets"), text: Binding(get: { p.chars ?? "" }, set: { p.chars = $0.isEmpty ? nil : $0 }), prompt: Text("[ ]"))
            }
            if p.border == "pixel" { TriStateRow(title: L("Bevel"), value: $p.bevel) }
            OptionalColorRow(title: L("Border color"), value: $p.borderColor)
            OptionalNumberRow(title: L("Border width"), value: $p.borderWidth, range: 0.5...4, initial: 1)
            OptionalNumberRow(title: L("Corner radius"), value: $p.radius, range: 0...20, initial: 6)
            OptionalNumberRow(title: L("Glow"), value: $p.glow, range: 0...10, initial: 3)
            if p.glow != nil { OptionalColorRow(title: L("Glow color"), value: $p.glowColor) }
            OptionalNumberRow(title: L("Shadow"), value: $p.shadow, range: 0...3, initial: 1)
            TriStateRow(title: L("Swap fill and text"), value: $p.invert)
        }
    }
}

struct OptionalColorRow: View {
    let title: String
    @Binding var value: String?

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? "#FFFFFF") : nil }))
            Spacer()
            if let v = value {
                ColorPicker("", selection: Binding(get: { Color(hexString: v) ?? .clear }, set: { value = $0.hexString }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.2f"

    var body: some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
    }
}

struct OptionalNumberRow: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let initial: Double

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? initial : nil })).frame(width: 150, alignment: .leading)
            if let v = value {
                Slider(value: Binding(get: { v }, set: { value = ($0 * 100).rounded() / 100 }), in: range)
                Text(String(format: "%.1f", v)).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            } else {
                Spacer()
                Text(L("Inherit")).foregroundStyle(.secondary)
            }
        }
    }
}

struct TriStateRow: View {
    let title: String
    @Binding var value: Bool?

    var body: some View {
        Picker(title, selection: $value) {
            Text(L("Inherit")).tag(Bool?.none)
            Text(L("On")).tag(Bool?.some(true))
            Text(L("Off")).tag(Bool?.some(false))
        }
    }
}

extension Role {
    static let allKeys = ["active", "primary", "accent", "operator", "suggestions", "danger", "warning", "success"]

    static func title(_ k: String) -> String {
        switch k {
        case "active": L("Active")
        case "primary": L("Primary")
        case "accent": L("Accent")
        case "operator": L("Operator")
        case "suggestions": L("Suggestions")
        case "danger": L("Danger")
        case "warning": L("Warning")
        default: L("Success")
        }
    }

    static func help(_ k: String) -> String {
        switch k {
        case "active": L("A switched-on button, the current space, the app in front in the Dock.")
        case "primary": L("Done, Send and other main actions.")
        case "accent": L("Highlights such as running dots in the Dock.")
        case "operator": L("Calculator’s ÷ × − + = keys.")
        case "suggestions": L("Typing suggestions.")
        case "danger": L("Badges and destructive actions. Falls back to Operator.")
        case "warning": L("Low battery and other warnings in widgets. Falls back to Operator.")
        default: L("Finished timers and other good news in widgets. Falls back to Active.")
        }
    }
}
