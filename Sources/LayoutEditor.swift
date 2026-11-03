import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The Layout Editor, a page in the Hub: a library on the left, the bar in the middle drawn with the current theme,
// the selected item's settings on the right. It writes the same layout.json people write by hand (docs/LAYOUTS.md).

final class LayoutEditorModel: ObservableObject {
    @Published var layouts = LayoutStore.shared.all
    @Published var draft: BarLayout
    @Published var saved: BarLayout?
    @Published var selection: Int?
    @Published var message = ""

    init() {
        draft = LayoutStore.shared.all.first ?? LayoutEditorModel.blank()
        saved = LayoutStore.shared.all.first
    }

    static func blank() -> BarLayout {
        var l = try! JSONDecoder().decode(BarLayout.self, from: Data(#"{"id":"","items":[]}"#.utf8))
        l.name = L("New Layout")
        l.id = ThemeStore.newID(l.name)
        l.author = NSFullUserName()
        return l
    }

    var isDirty: Bool { draft != saved }

    func select(_ l: BarLayout) { draft = l; saved = l; selection = nil; message = "" }

    func newLayout() {
        draft = Self.blank()
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, front != Bundle.main.bundleIdentifier { draft.apps = [front] }
        saved = nil
        selection = nil
        message = ""
    }

    func insert(_ item: LayoutItem, at i: Int? = nil) {
        let at = min(i ?? draft.items.count, draft.items.count)
        draft.items.insert(item, at: at)
        selection = at
    }

    func move(from: Int, to: Int) {
        guard from != to, draft.items.indices.contains(from) else { return }
        let item = draft.items.remove(at: from)
        let at = min(to > from ? to - 1 : to, draft.items.count)
        draft.items.insert(item, at: at)
        selection = at
    }

    func removeSelected() {
        guard let i = selection, draft.items.indices.contains(i) else { return }
        draft.items.remove(at: i)
        selection = draft.items.isEmpty ? nil : min(i, draft.items.count - 1)
    }

    func save() {
        func clean(_ l: [LayoutItem]) -> [LayoutItem] {
            l.map { i in
                var i = i
                if let a = i.action, [a.shortcut, a.menu, a.open].allSatisfy({ ($0 ?? "").isEmpty }) { i.action = nil }
                i.items = i.items.map(clean)
                return i
            }
        }
        draft.items = clean(draft.items)
        do {
            draft = try LayoutStore.shared.save(draft)
            saved = draft
            layouts = LayoutStore.shared.all
            message = L("Saved")
        } catch { message = error.localizedDescription }
    }

    func delete() {
        LayoutStore.shared.delete(draft.id)
        layouts = LayoutStore.shared.all
        if let first = layouts.first { select(first) } else { newLayout() }
    }

    func revert() { if let saved { draft = saved } }

    func addApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !draft.apps.contains(id) { draft.apps.append(id) }
    }

    func exportLayout() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = draft.id + ".json"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try LayoutStore.encode(draft).write(to: url, options: .atomic); message = L("Exported") } catch { message = error.localizedDescription }
    }
}

extension LayoutStore {
    static func encode(_ l: BarLayout) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(l)
    }

    /// Writes layout.json into the layout's folder (a new folder named by its id when it has none).
    @discardableResult func save(_ l: BarLayout) throws -> BarLayout {
        let fm = FileManager.default
        var l = l
        let to: URL
        if let base = l.baseURL {
            to = base
        } else {
            if let old = locations[l.id] { try? fm.removeItem(at: old) }
            to = folder.appendingPathComponent(l.id, isDirectory: true)
        }
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        try LayoutStore.encode(l).write(to: to.appendingPathComponent("layout.json"), options: .atomic)
        l.baseURL = to
        reload()
        return l
    }
}

// MARK: views

struct LayoutEditorView: View {
    @ObservedObject var m: LayoutEditorModel
    @ObservedObject var d: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                LayoutList(m: m)
                Divider()
                LayoutLibrary(m: m)
            }
            .frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                LayoutCanvas(m: m, d: d)
                Divider()
                LayoutInspector(m: m)
                Divider()
                HStack {
                    Button(L("Delete"), role: .destructive, action: m.delete).disabled(m.saved == nil)
                    Text(m.message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Revert"), action: m.revert).disabled(!m.isDirty || m.saved == nil)
                    Button(L("Export…"), action: m.exportLayout)
                    Button(L("Save"), action: m.save).keyboardShortcut("s").disabled(!m.isDirty)
                }
                .padding(12)
            }
        }
    }
}

private struct LayoutList: View {
    @ObservedObject var m: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(m.layouts) { l in
                        Button { m.select(l) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.name).lineLimit(1)
                                Text(l.apps.map(LayoutList.appName).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 6).fill(m.draft.id == l.id ? Color.accentColor.opacity(0.22) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                    if m.layouts.isEmpty { Text(L("No layouts yet.")).foregroundStyle(.secondary).padding(8) }
                }
                .padding(8)
            }
            Button(L("New Layout"), action: m.newLayout).padding(10)
        }
    }

    static func appName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }
}

/// What can go on the bar. Drag onto the bar, or click to add at the end.
private struct LayoutLibrary: View {
    @ObservedObject var m: LayoutEditorModel

    static var entries: [(String, String, LayoutItem)] { builtIn + ScriptWidgetStore.shared.all.map { w in
        (w.name, "curlybraces", LayoutItem(type: "widget", widget: "script:" + w.id))
    } }

    private static let builtIn: [(String, String, LayoutItem)] = [
        (L("Button"), "button.horizontal", LayoutItem(label: L("Button"))),
        (L("Icon Button"), "star", LayoutItem(icon: "star")),
        (L("Group"), "rectangle.split.2x1", LayoutItem(type: "group", items: [LayoutItem(icon: "chevron.left"), LayoutItem(icon: "chevron.right")])),
        (L("Text"), "textformat", LayoutItem(type: "text", label: L("Text"))),
        (L("Space"), "arrow.left.and.right", LayoutItem(type: "space")),
    ] + WidgetKind.allCases.map { k in (k.name, k.symbol, LayoutItem(type: "widget", widget: k.rawValue)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Library")).font(.headline).padding(.horizontal, 10).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Self.entries.enumerated()), id: \.offset) { i, e in
                        Label(e.0, systemImage: e.1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { m.insert(e.2) }
                            .onDrag { NSItemProvider(object: "new:\(i)" as NSString) }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(maxHeight: 330)
    }
}

/// The bar being edited: each item is drawn by the real layout renderer, so it looks the way it will on the Touch Bar.
private struct LayoutCanvas: View {
    @ObservedObject var m: LayoutEditorModel
    @ObservedObject var d: AppState

    var body: some View {
        let t = d.theme
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.spacing) {
                    ForEach(Array(m.draft.items.enumerated()), id: \.offset) { i, item in
                        cell(item)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: m.selection == i ? 2 : 0).padding(-3))
                            .contentShape(Rectangle())
                            .onTapGesture { m.selection = i }
                            .onDrag { m.selection = i; return NSItemProvider(object: "item:\(i)" as NSString) }
                            .onDrop(of: [.text], delegate: ItemDrop(m: m, index: i))
                    }
                    Color.clear.frame(width: 80, height: Metrics.buttonHeight)
                        .overlay(Text(m.draft.items.isEmpty ? L("Drag items here") : "").font(.caption).foregroundStyle(.white.opacity(0.5)).fixedSize())
                        .onDrop(of: [.text], delegate: ItemDrop(m: m, index: m.draft.items.count))
                }
                .frame(height: Metrics.barHeight)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background { if let b = t.skin?.bar { SkinBarBackground(style: b, theme: t) } else { Color.black } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .environment(\.theme, t)
                .font(t.font(14))
                .textCase(t.letterCase)
            }
            Text(L("Drag to reorder. Saved layouts show on the Touch Bar when one of their apps is in front."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }

    @ViewBuilder private func cell(_ item: LayoutItem) -> some View {
        if item.type == "space" {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 60, height: Metrics.buttonHeight)
                .overlay(Image(systemName: "arrow.left.and.right").foregroundStyle(.white.opacity(0.5)))
        } else {
            HStack(spacing: Metrics.spacing) { LayoutBar(d: d, layout: single(item)) }
                .allowsHitTesting(false)
        }
    }

    private func single(_ item: LayoutItem) -> BarLayout {
        var l = m.draft
        l.items = [item]
        return l
    }
}

private struct ItemDrop: DropDelegate {
    let m: LayoutEditorModel
    let index: Int

    func performDrop(info: DropInfo) -> Bool {
        guard let p = info.itemProviders(for: [.text]).first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { s, _ in
            guard let s = s as? String else { return }
            DispatchQueue.main.async {
                if s.hasPrefix("item:"), let from = Int(s.dropFirst(5)) {
                    m.move(from: from, to: index)
                } else if s.hasPrefix("new:"), let i = Int(s.dropFirst(4)), LayoutLibrary.entries.indices.contains(i) {
                    m.insert(LayoutLibrary.entries[i].2, at: index)
                }
            }
        }
        return true
    }
}

private struct LayoutInspector: View {
    @ObservedObject var m: LayoutEditorModel

    var body: some View {
        Form {
            if let i = m.selection, m.draft.items.indices.contains(i) {
                ItemSettings(item: $m.draft.items[i], remove: m.removeSelected)
            } else {
                Section(L("Layout")) {
                    TextField(L("Name"), text: $m.draft.name)
                    TextField(L("Author"), text: $m.draft.author)
                    TextField(L("Description"), text: $m.draft.description)
                }
                Section(L("Shows for")) {
                    ForEach(m.draft.apps, id: \.self) { a in
                        HStack {
                            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 18, height: 18)
                            }
                            Text(LayoutList.appName(a))
                            Text(a).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { m.draft.apps.removeAll { $0 == a } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button(L("Add App…"), action: m.addApp)
                        Menu(L("Running Apps")) {
                            ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }, id: \.processIdentifier) { a in
                                if let id = a.bundleIdentifier { Button(a.localizedName ?? id) { if !m.draft.apps.contains(id) { m.draft.apps.append(id) } } }
                            }
                        }
                        .fixedSize()
                    }
                }
                Section { Text(L("Select an item on the bar to change it.")).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ItemSettings: View {
    @Binding var item: LayoutItem
    let remove: () -> Void

    var body: some View {
        let type = item.type ?? "button"
        Section(title(type)) {
            switch type {
            case "space":
                Text(L("A space pushes the items after it to the right.")).foregroundStyle(.secondary)
            case "text":
                TextField(L("Text"), text: text(\.label))
            case "widget":
                Picker(L("Widget"), selection: Binding(get: { item.widget ?? "clock" }, set: { item.widget = $0 })) {
                    ForEach(WidgetKind.allCases) { Text($0.name).tag($0.rawValue) }
                    ForEach(ScriptWidgetStore.shared.all) { Text($0.name).tag("script:" + $0.id) }
                }
                if item.widget == WidgetKind.worldClock.rawValue {
                    Picker(L("City"), selection: Binding(get: { item.option ?? WidgetSettings.shared.worldClockZone }, set: { item.option = $0 })) {
                        ForEach(WidgetSettings.zones, id: \.self) { Text(WidgetSettings.city($0)).tag($0) }
                    }
                }
            case "group":
                ButtonFields(item: $item, showsAction: false)
                ForEach(Array((item.items ?? []).enumerated()), id: \.offset) { i, _ in
                    DisclosureGroup(groupTitle(i)) {
                        ButtonFields(item: Binding(get: { item.items?[i] ?? LayoutItem() }, set: { item.items?[i] = $0 }), showsAction: true)
                        Button(L("Remove from Group"), role: .destructive) { item.items?.remove(at: i) }.disabled((item.items?.count ?? 0) < 2)
                    }
                }
                Button(L("Add Button to Group")) { item.items = (item.items ?? []) + [LayoutItem(icon: "circle")] }
            default:
                ButtonFields(item: $item, showsAction: true)
            }
        }
        Section { Button(L("Remove from Bar"), role: .destructive, action: remove) }
    }

    private func title(_ type: String) -> String {
        switch type {
        case "space": L("Space")
        case "text": L("Text")
        case "widget": L("Widget")
        case "group": L("Group")
        default: L("Button")
        }
    }

    private func groupTitle(_ i: Int) -> String {
        let b = item.items?[i]
        return b?.label ?? b?.icon ?? String(format: L("Button %d"), i + 1)
    }

    private func text(_ k: WritableKeyPath<LayoutItem, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: k] ?? "" }, set: { item[keyPath: k] = $0.isEmpty ? nil : $0 })
    }
}

/// Label, icon, role, width and what a button does.
private struct ButtonFields: View {
    @Binding var item: LayoutItem
    let showsAction: Bool

    var body: some View {
        TextField(L("Label"), text: text(\.label))
        HStack {
            TextField(L("Icon"), text: text(\.icon), prompt: Text("star"))
            if let i = item.icon, !i.hasPrefix("image:") { Image(systemName: i).frame(width: 22) }
            Menu(L("Common symbols")) {
                ForEach(CommonSymbols.list, id: \.self) { s in Button { item.icon = s } label: { Label(s, systemImage: s) } }
            }
            .fixedSize()
        }
        Picker(L("Role"), selection: Binding(get: { item.role ?? "" }, set: { item.role = $0.isEmpty ? nil : $0 })) {
            Text(L("None")).tag("")
            ForEach(Role.allKeys, id: \.self) { Text(Role.title($0)).tag($0) }
        }
        HStack {
            Toggle(L("Fixed width"), isOn: Binding(get: { item.width != nil }, set: { item.width = $0 ? 72 : nil }))
            if let w = item.width {
                Slider(value: Binding(get: { w }, set: { item.width = $0.rounded() }), in: 20...400)
                Text("\(Int(w))").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
        if showsAction {
            Picker(L("Does"), selection: Binding(get: { kind }, set: { setKind($0) })) {
                Text(L("Nothing")).tag("")
                Text(L("Keyboard shortcut")).tag("shortcut")
                Text(L("Menu command")).tag("menu")
                Text(L("Open a link or app")).tag("open")
            }
            switch kind {
            case "shortcut":
                TextField(L("Shortcut"), text: action(\.shortcut), prompt: Text("cmd+shift+b"))
                if let s = item.action?.shortcut, !s.isEmpty, KeyNames.parse(s) == nil {
                    Text(L("Can’t read this shortcut. Use names like cmd, shift, alt, ctrl and a key: cmd+shift+b, f5.")).font(.caption).foregroundStyle(.orange)
                }
            case "menu":
                TextField(L("Menu item title"), text: action(\.menu), prompt: Text("Show Sidebar"))
            case "open":
                TextField(L("Link or bundle identifier"), text: action(\.open), prompt: Text("https://… or com.apple.Music"))
            default: EmptyView()
            }
        }
    }

    private var kind: String {
        if item.action?.shortcut != nil { return "shortcut" }
        if item.action?.menu != nil { return "menu" }
        if item.action?.open != nil { return "open" }
        return ""
    }

    private func setKind(_ k: String) {
        switch k {
        case "shortcut": item.action = LayoutAction(shortcut: "")
        case "menu": item.action = LayoutAction(menu: "")
        case "open": item.action = LayoutAction(open: "")
        default: item.action = nil
        }
    }

    private func text(_ k: WritableKeyPath<LayoutItem, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: k] ?? "" }, set: { item[keyPath: k] = $0.isEmpty ? nil : $0 })
    }

    /// Empty text keeps the action's kind, so the field doesn't vanish while typing.
    private func action(_ k: WritableKeyPath<LayoutAction, String?>) -> Binding<String> {
        Binding(get: { item.action?[keyPath: k] ?? "" }, set: { v in
            var a = item.action ?? LayoutAction()
            a[keyPath: k] = v
            item.action = a
        })
    }
}
