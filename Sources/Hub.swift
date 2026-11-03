import AppKit
import SwiftUI

/// The GlassBar Hub window: installed themes and the theme store. Built when opened and let go when closed,
/// so nothing of it stays in memory while it isn't on screen.
enum Hub {
    enum Page: Hashable { case themes, store }

    private static var window: NSWindow?
    private static var delegate: HubWindowDelegate?
    private static var model: HubModel?

    static func open(_ d: AppState, _ page: Page = .themes) {
        NSApp.activate(ignoringOtherApps: true)
        if let window, let model {
            model.page = page
            window.makeKeyAndOrderFront(nil)
            return
        }
        let m = HubModel(d, page)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "GlassBar Hub"
        w.contentView = NSHostingView(rootView: HubView(m: m).environmentObject(d))
        w.contentMinSize = NSSize(width: 720, height: 460)
        w.isReleasedWhenClosed = false
        w.center()
        delegate = HubWindowDelegate { window = nil; delegate = nil; model = nil }
        w.delegate = delegate
        window = w
        model = m
        w.makeKeyAndOrderFront(nil)
    }
}

private final class HubWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ n: Notification) { onClose() }
}

/// One theme in the store's index.json.
struct StoreItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var author = ""
    var version = 1
    var description = ""
    /// files in the theme's folder, theme.json and preview.png included
    var files: [String] = []

    enum CodingKeys: String, CodingKey { case id, name, author, version, description, files }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        author = (try? c.decode(String.self, forKey: .author)) ?? ""
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        files = (try? c.decode([String].self, forKey: .files)) ?? []
    }

    /// Ids and file names come from the internet: nothing that could leave the theme's folder.
    var isSafe: Bool {
        let ok = { (s: String) in !s.isEmpty && !s.hasPrefix(".") && !s.contains("/") && !s.contains("\\") && !s.contains("..") }
        return ok(id) && id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && files.allSatisfy(ok) && files.contains("theme.json")
    }
}

final class HubModel: ObservableObject {
    let d: AppState
    @Published var page: Hub.Page
    @Published var themes: [Theme] = []
    @Published var storeItems: [StoreItem] = []
    @Published var storeState = StoreState.idle
    @Published var previews: [String: NSImage] = [:]
    @Published var busy: Set<String> = []
    @Published var message = ""

    enum StoreState: Equatable { case idle, loading, loaded, failed(String) }

    /// the community themes folder of the repo; `defaults write com.yukselozge.GlassBar storeURL file:///…/themes/` to test a local copy
    static var storeBase: URL {
        URL(string: Defaults.string("storeURL")).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(string: "https://raw.githubusercontent.com/\(UpdateChecker.repository)/main/themes/")!
    }

    init(_ d: AppState, _ page: Hub.Page) {
        self.d = d
        self.page = page
        refreshThemes()
    }

    func refreshThemes() {
        ThemeStore.shared.reload()
        themes = ThemeStore.shared.all
        for t in themes where previews["local:" + t.id] == nil {
            if let u = ThemeStore.shared.preview(t), let i = NSImage(contentsOf: u) { previews["local:" + t.id] = i }
        }
    }

    func apply(_ t: Theme) { d.apply(t) }

    func delete(_ t: Theme) {
        if d.theme.id == t.id { d.apply(.classic) }
        ThemeStore.shared.delete(t.id)
        previews["local:" + t.id] = nil
        refreshThemes()
    }

    func reveal(_ t: Theme) {
        if let u = ThemeStore.shared.locations[t.id] { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: ThemeStore.shared.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ThemeStore.shared.folder)
    }

    // MARK: store

    func loadStore(force: Bool = false) {
        if storeState == .loading || (storeState == .loaded && !force) { return }
        storeState = .loading
        let base = HubModel.storeBase
        URLSession.shared.dataTask(with: base.appendingPathComponent("index.json")) { data, response, error in
            let items = data.flatMap { try? JSONDecoder().decode([String: [StoreItem]].self, from: $0) }?["themes"]
            DispatchQueue.main.async {
                guard let items, (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true else {
                    SystemControl.log("store: could not load \(base.absoluteString)index.json: \(error?.localizedDescription ?? "bad index")")
                    self.storeState = .failed(L("The theme store couldn't be reached. Check your connection and try again."))
                    return
                }
                self.storeItems = items.filter(\.isSafe)
                self.storeState = .loaded
                for item in self.storeItems where item.files.contains("preview.png") { self.loadPreview(item) }
            }
        }.resume()
    }

    private func loadPreview(_ item: StoreItem) {
        let key = "store:\(item.id):\(item.version)"
        guard previews[key] == nil else { return }
        let url = HubModel.storeBase.appendingPathComponent(item.id).appendingPathComponent("preview.png")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let i = NSImage(data: data) else { return }
            DispatchQueue.main.async { self.previews[key] = i }
        }.resume()
    }

    func installed(_ item: StoreItem) -> Theme? { ThemeStore.shared.userThemes.first { $0.id == item.id } }

    /// Downloads every file of the theme into a temporary package, then installs and applies it.
    func get(_ item: StoreItem) {
        guard !busy.contains(item.id) else { return }
        busy.insert(item.id)
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("GlassBar-store-\(UUID().uuidString)")
            .appendingPathComponent(item.id + ".glasstheme")
        let group = DispatchGroup()
        var failed = false
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for f in item.files {
            group.enter()
            let url = HubModel.storeBase.appendingPathComponent(item.id).appendingPathComponent(f)
            URLSession.shared.dataTask(with: url) { data, response, _ in
                let ok = (response as? HTTPURLResponse).map { $0.statusCode == 200 } ?? true
                if let data, ok { try? data.write(to: folder.appendingPathComponent(f)) } else { failed = true }
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) {
            self.busy.remove(item.id)
            defer { try? fm.removeItem(at: folder.deletingLastPathComponent()) }
            do {
                if failed { throw CocoaError(.fileReadUnknown) }
                if let old = ThemeStore.shared.locations[item.id] { try? fm.trashItem(at: old, resultingItemURL: nil) }
                let t = try ThemeStore.shared.install(folder)
                self.previews["local:" + t.id] = nil
                self.refreshThemes()
                self.d.apply(t)
                self.message = String(format: L("%@ is installed and on your Touch Bar."), t.name)
            } catch {
                SystemControl.log("store: could not install \(item.id): \(error.short)")
                self.message = String(format: L("%@ couldn't be installed. Try again later."), item.name)
            }
        }
    }
}

// MARK: views

struct HubView: View {
    @ObservedObject var m: HubModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { m.page }, set: { if let p = $0 { m.page = p } })) {
                Label(L("Themes"), systemImage: "paintpalette").tag(Hub.Page.themes)
                Label(L("Store"), systemImage: "bag").tag(Hub.Page.store)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch m.page {
            case .themes: ThemesPage(m: m)
            case .store: StorePage(m: m)
            }
        }
    }
}

private struct ThemesPage: View {
    @ObservedObject var m: HubModel
    @EnvironmentObject var d: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Themes")).font(.largeTitle.bold())
                    Spacer()
                    Button(L("Open Themes Folder")) { m.openFolder() }
                    Button(L("Reload Themes")) { m.refreshThemes(); d.theme = ThemeStore.shared.theme(id: d.theme.id) ?? .classic }
                }
                Text(L("Write your own theme as JSON in the themes folder. The guide is in docs/THEMES.md on GitHub."))
                    .foregroundStyle(.secondary)
                ForEach(m.themes) { t in
                    ThemeCard(name: t.displayName, author: t.author, detail: "", preview: m.previews["local:" + t.id], theme: t) {
                        if d.theme.id == t.id {
                            Label(L("In Use"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button(L("Apply")) { m.apply(t) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        }
                        if !t.isBuiltIn {
                            Menu {
                                Button(L("Show in Finder")) { m.reveal(t) }
                                Button(L("Move to Trash"), role: .destructive) { m.delete(t) }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct StorePage: View {
    @ObservedObject var m: HubModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Store")).font(.largeTitle.bold())
                    Spacer()
                    Button { m.loadStore(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .help(L("Refresh"))
                }
                Text(L("Themes made by GlassBar users. Made one yourself? Share it with a pull request, see themes/README.md on GitHub."))
                    .foregroundStyle(.secondary)
                if !m.message.isEmpty { Text(m.message).font(.callout) }
                switch m.storeState {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding(40)
                case .failed(let s): Text(s).foregroundStyle(.secondary).padding(.vertical, 30)
                case .loaded:
                    if m.storeItems.isEmpty { Text(L("No themes yet.")).foregroundStyle(.secondary) }
                    ForEach(m.storeItems) { item in
                        let local = m.installed(item)
                        ThemeCard(name: item.name, author: item.author, detail: item.description,
                                  preview: m.previews["store:\(item.id):\(item.version)"], theme: nil) {
                            if m.busy.contains(item.id) {
                                ProgressView().controlSize(.small)
                            } else if let local, local.version >= item.version {
                                Button(L("Installed")) { m.apply(local) }.help(L("Apply"))
                            } else {
                                Button(local == nil ? L("Get") : L("Update")) { m.get(item) }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear { m.loadStore() }
    }
}

/// A theme with its bar screenshot. The screenshot is the whole Touch Bar, far too wide for a card, so it's shown
/// as its left and right halves stacked.
private struct ThemeCard<Actions: View>: View {
    let name: String
    let author: String
    let detail: String
    let preview: NSImage?
    let theme: Theme?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let preview {
                    VStack(spacing: 2) {
                        half(preview, left: true)
                        half(preview, left: false)
                    }
                } else if let theme {
                    SwatchBar(theme: theme)
                } else {
                    Color.black.frame(height: 62)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if !author.isEmpty { Text(String(format: L("by %@"), author)).font(.caption).foregroundStyle(.secondary) }
                    if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                actions()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func half(_ i: NSImage, left: Bool) -> some View {
        GeometryReader { g in
            Image(nsImage: i).resizable().interpolation(.high)
                .frame(width: g.size.width * 2, height: g.size.height)
                .offset(x: left ? 0 : -g.size.width)
        }
        .aspectRatio(i.size.width / 2 / max(i.size.height, 1), contentMode: .fit)
        .clipped()
    }
}

/// For a theme without a screenshot: its bar color and a few buttons in its colors.
private struct SwatchBar: View {
    let theme: Theme

    var body: some View {
        let l = theme.layer(nil), active = theme.layer(.active), primary = theme.layer(.primary)
        let bar = theme.color(theme.skin?.bar?.fill) ?? .black
        HStack(spacing: 6) {
            ForEach(Array(["esc", "<", ">", "Aa", "+", "☀︎", "◀︎)"].enumerated()), id: \.offset) { i, s in
                let layer = i == 4 ? primary : i == 6 ? active : l
                Text(theme.cased(s)).font(theme.font(13)).foregroundStyle(layer.text)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: min(theme.isSkin ? layer.radius : theme.cornerRadius, 15))
                        .fill(theme.isSkin ? (layer.fill ?? .clear) : theme.glassTint.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: min(theme.isSkin ? layer.radius : theme.cornerRadius, 15))
                        .strokeBorder(layer.borderColor, lineWidth: theme.isSkin && layer.border != "none" ? max(layer.borderWidth, 1) : 0))
            }
        }
        .padding(8)
        .frame(height: 62)
        .background(bar)
    }
}
