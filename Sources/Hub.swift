import AppKit
import SwiftUI

/// The GlassBar Hub window: the store for themes and layouts, and what you have installed. Built when opened and
/// let go when closed, so nothing of it stays in memory while it isn't on screen.
enum Hub {
    enum Page: Hashable {
        case featured, new, popular, updated, name, category(String), installed, updates
    }
    enum Kind: String { case themes, layouts }

    private static var window: NSWindow?
    private static var delegate: HubWindowDelegate?
    private static var model: HubModel?

    static func open(_ d: AppState, _ page: Page = .featured, _ kind: Kind = .themes) {
        NSApp.activate(ignoringOtherApps: true)
        if let window, let model {
            model.kind = kind
            model.page = page
            window.makeKeyAndOrderFront(nil)
            return
        }
        let m = HubModel(d, page, kind)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "GlassBar Hub"
        w.contentView = NSHostingView(rootView: HubView(m: m).environmentObject(d))
        w.contentMinSize = NSSize(width: 860, height: 520)
        w.isReleasedWhenClosed = false
        w.center()
        delegate = HubWindowDelegate { window = nil; delegate = nil; model = nil }
        w.delegate = delegate
        window = w
        model = m
        w.makeKeyAndOrderFront(nil)
        m.loadStore()
    }
}

private final class HubWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ n: Notification) { onClose() }
}

/// One theme or layout in the store's index.json.
struct StoreItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var author = ""
    var version = 1
    var description = ""
    var category = ""
    /// "2026-11-03"
    var added = ""
    var updated = ""
    var featured = false
    /// files in the item's folder, theme.json or layout.json and preview.png included
    var files: [String] = []

    enum CodingKeys: String, CodingKey { case id, name, author, version, description, category, added, updated, featured, files }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        name = s(.name).isEmpty ? id : s(.name)
        author = s(.author); description = s(.description); category = s(.category)
        added = s(.added); updated = s(.updated).isEmpty ? s(.added) : s(.updated)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        featured = (try? c.decode(Bool.self, forKey: .featured)) ?? false
        files = (try? c.decode([String].self, forKey: .files)) ?? []
    }

    /// Ids and file names come from the internet: nothing that could leave the item's folder.
    func isSafe(_ main: String) -> Bool {
        let ok = { (s: String) in !s.isEmpty && !s.hasPrefix(".") && !s.contains("/") && !s.contains("\\") && !s.contains("..") }
        return ok(id) && id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && files.allSatisfy(ok) && files.contains(main)
    }

    /// name of the zip the GitHub workflow uploads to the "themes" or "layouts" release
    var assetName: String { "\(id)-\(version).zip" }
}

final class HubModel: ObservableObject {
    let d: AppState
    @Published var page: Hub.Page
    @Published var kind: Hub.Kind
    @Published var search = ""
    @Published var themes: [Theme] = []
    @Published var layouts: [BarLayout] = []
    @Published var catalog: [Hub.Kind: [StoreItem]] = [:]
    @Published var storeState = StoreState.idle
    /// installs per "kind/id", from the download counts of the release zips; empty when GitHub can't be asked
    @Published var installs: [String: Int] = [:]
    @Published var previews: [String: NSImage] = [:]
    @Published var busy: Set<String> = []
    @Published var message = ""
    @Published var comingSoon: ComingSoon?

    enum StoreState: Equatable { case idle, loading, loaded, failed }

    struct ComingSoon: Identifiable {
        let title: String
        let version: String
        var id: String { title }
    }

    /// release zips by "kind/asset name"
    private var assets: [String: URL] = [:]

    /// the repo's themes folder; `defaults write com.yukselozge.GlassBar storeURL file:///…/themes/` to test a local copy.
    /// Layouts live next to it in layouts/.
    static var themesBase: URL {
        URL(string: Defaults.string("storeURL")).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(string: "https://raw.githubusercontent.com/\(UpdateChecker.repository)/main/themes/")!
    }
    static func base(_ k: Hub.Kind) -> URL {
        k == .themes ? themesBase : themesBase.deletingLastPathComponent().appendingPathComponent("layouts/")
    }
    static var isLocalStore: Bool { themesBase.isFileURL }

    init(_ d: AppState, _ page: Hub.Page, _ kind: Hub.Kind) {
        self.d = d
        self.page = page
        self.kind = kind
        refreshLocal()
    }

    func refreshLocal() {
        ThemeStore.shared.reload()
        LayoutStore.shared.reload()
        themes = ThemeStore.shared.all
        layouts = LayoutStore.shared.all
        for t in themes where previews["local:themes:" + t.id] == nil {
            if let u = ThemeStore.shared.preview(t), let i = NSImage(contentsOf: u) { previews["local:themes:" + t.id] = i }
        }
        for l in layouts where previews["local:layouts:" + l.id] == nil {
            if let u = LayoutStore.shared.preview(l), let i = NSImage(contentsOf: u) { previews["local:layouts:" + l.id] = i }
        }
        d.objectWillChange.send()
    }

    func apply(_ t: Theme) { d.apply(t) }

    func delete(_ t: Theme) {
        if d.theme.id == t.id { d.apply(.classic) }
        ThemeStore.shared.delete(t.id)
        previews["local:themes:" + t.id] = nil
        refreshLocal()
    }

    func delete(_ l: BarLayout) {
        LayoutStore.shared.delete(l.id)
        previews["local:layouts:" + l.id] = nil
        refreshLocal()
    }

    func reveal(_ url: URL?) {
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func openFolder() {
        let f = kind == .themes ? ThemeStore.shared.folder : LayoutStore.shared.folder
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        NSWorkspace.shared.open(f)
    }

    func openGitHub(_ path: String) {
        if let u = URL(string: "https://github.com/\(UpdateChecker.repository)/\(path)") { NSWorkspace.shared.open(u) }
    }

    // MARK: lists

    var storeItems: [StoreItem] { catalog[kind] ?? [] }
    var categories: [String] { Array(Set(storeItems.map(\.category).filter { !$0.isEmpty })).sorted() }
    var featured: StoreItem? { storeItems.first(where: \.featured) ?? storeItems.first }
    var updates: [StoreItem] { storeItems.filter { i in installedVersion(i).map { $0 < i.version } ?? false } }
    func installCount(_ i: StoreItem) -> Int? { installs[kind.rawValue + "/" + i.id] }
    func preview(_ i: StoreItem) -> NSImage? { previews["store:\(kind.rawValue):\(i.id):\(i.version)"] }

    func items(_ p: Hub.Page) -> [StoreItem] {
        var list = storeItems
        if !search.isEmpty {
            list = list.filter { "\($0.name) \($0.author) \($0.description) \($0.category)".localizedCaseInsensitiveContains(search) }
        }
        switch p {
        case .new, .featured: return list.sorted { $0.added > $1.added }
        case .popular: return list.sorted { (installCount($0) ?? 0) > (installCount($1) ?? 0) }
        case .updated: return list.sorted { $0.updated > $1.updated }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .category(let c): return list.filter { $0.category == c }.sorted { $0.name < $1.name }
        case .updates: return updates
        case .installed: return []
        }
    }

    // MARK: store

    func loadStore(force: Bool = false) {
        if storeState == .loading || (storeState == .loaded && !force) { return }
        storeState = .loading
        let group = DispatchGroup()
        var failed = false
        for k in [Hub.Kind.themes, .layouts] {
            group.enter()
            let base = HubModel.base(k)
            URLSession.shared.dataTask(with: base.appendingPathComponent("index.json")) { data, response, error in
                let items = data.flatMap { try? JSONDecoder().decode([String: [StoreItem]].self, from: $0) }?[k.rawValue]
                DispatchQueue.main.async {
                    if let items, (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true {
                        self.catalog[k] = items.filter { $0.isSafe(k == .themes ? "theme.json" : "layout.json") }
                        for item in self.catalog[k] ?? [] where item.files.contains("preview.png") { self.loadPreview(item, k) }
                    } else {
                        SystemControl.log("store: could not load \(base.absoluteString)index.json: \(error?.localizedDescription ?? "bad index")")
                        failed = failed || k == .themes
                    }
                    group.leave()
                }
            }.resume()
            if !HubModel.isLocalStore { loadInstallCounts(k) }
        }
        group.notify(queue: .main) { self.storeState = failed ? .failed : .loaded }
    }

    /// GitHub counts downloads of release files, so every theme and layout is also a zip in the "themes" or "layouts"
    /// release (made by .github/workflows/store.yml) and installing downloads that zip.
    private func loadInstallCounts(_ k: Hub.Kind) {
        guard let url = URL(string: "https://api.github.com/repos/\(UpdateChecker.repository)/releases/tags/\(k.rawValue)") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            var counts: [String: Int] = [:], urls: [String: URL] = [:]
            for a in json?["assets"] as? [[String: Any]] ?? [] {
                guard let name = a["name"] as? String, name.hasSuffix(".zip") else { continue }
                // "paper-2.zip": every version counts for the item
                let stem = name.dropLast(4)
                guard let dash = stem.lastIndex(of: "-") else { continue }
                counts[k.rawValue + "/" + stem[..<dash], default: 0] += a["download_count"] as? Int ?? 0
                if let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) { urls[k.rawValue + "/" + name] = u }
            }
            DispatchQueue.main.async {
                self.installs.merge(counts) { _, b in b }
                self.assets.merge(urls) { _, b in b }
            }
        }.resume()
    }

    private func loadPreview(_ item: StoreItem, _ k: Hub.Kind) {
        let key = "store:\(k.rawValue):\(item.id):\(item.version)"
        guard previews[key] == nil else { return }
        let url = HubModel.base(k).appendingPathComponent(item.id).appendingPathComponent("preview.png")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let i = NSImage(data: data) else { return }
            DispatchQueue.main.async { self.previews[key] = i }
        }.resume()
    }

    func installedTheme(_ item: StoreItem) -> Theme? { ThemeStore.shared.userThemes.first { $0.id == item.id } }

    func installedVersion(_ item: StoreItem) -> Int? {
        kind == .themes ? installedTheme(item)?.version : LayoutStore.shared.all.first { $0.id == item.id }?.version
    }

    /// Downloads the item (its release zip, or its files one by one) and installs it; a theme is also applied.
    func get(_ item: StoreItem) {
        let k = kind, key = k.rawValue + "/" + item.id
        guard !busy.contains(key) else { return }
        busy.insert(key)
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("GlassBar-store-\(UUID().uuidString)")
        try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let zip = assets[k.rawValue + "/" + item.assetName]
        let finish = { (folder: URL?) in
            DispatchQueue.main.async {
                self.busy.remove(key)
                defer { try? fm.removeItem(at: temp) }
                do {
                    guard let folder else { throw CocoaError(.fileReadUnknown) }
                    if k == .themes {
                        if let old = ThemeStore.shared.locations[item.id] { try? fm.trashItem(at: old, resultingItemURL: nil) }
                        let t = try ThemeStore.shared.install(folder)
                        self.previews["local:themes:" + t.id] = nil
                        self.d.apply(t)
                        self.message = String(format: L("%@ is installed and on your Touch Bar."), t.name)
                    } else {
                        let l = try LayoutStore.shared.install(folder)
                        self.previews["local:layouts:" + l.id] = nil
                        self.message = String(format: L("%@ is installed. It shows on the Touch Bar when its app is in front."), l.name)
                    }
                    self.refreshLocal()
                    if zip != nil { self.installs[key, default: 0] += 1 }
                } catch {
                    SystemControl.log("store: could not install \(key): \(error.short)")
                    self.message = String(format: L("%@ couldn't be installed. Try again later."), item.name)
                }
            }
        }
        if let zip {
            URLSession.shared.downloadTask(with: zip) { file, response, _ in
                guard let file, (response as? HTTPURLResponse)?.statusCode == 200 else { return finish(nil) }
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", file.path, temp.path]
                try? unzip.run()
                unzip.waitUntilExit()
                let folder = temp.appendingPathComponent(item.id)
                finish(unzip.terminationStatus == 0 && fm.fileExists(atPath: folder.path) ? folder : nil)
            }.resume()
            return
        }
        let folder = temp.appendingPathComponent(k == .themes ? item.id + ".glasstheme" : item.id)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let group = DispatchGroup()
        var failed = false
        for f in item.files {
            group.enter()
            let url = HubModel.base(k).appendingPathComponent(item.id).appendingPathComponent(f)
            URLSession.shared.dataTask(with: url) { data, response, _ in
                let ok = (response as? HTTPURLResponse).map { $0.statusCode == 200 } ?? true
                if let data, ok { try? data.write(to: folder.appendingPathComponent(f)) } else { failed = true }
                group.leave()
            }.resume()
        }
        group.notify(queue: .global()) { finish(failed ? nil : folder) }
    }
}

// MARK: views

struct HubView: View {
    @ObservedObject var m: HubModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { m.page }, set: { if let p = $0 { m.page = p } })) {
                Section(L("Store")) {
                    Label(L("Featured"), systemImage: "star").tag(Hub.Page.featured)
                    Label(L("New"), systemImage: "sparkles").tag(Hub.Page.new)
                    Label(L("Most Installed"), systemImage: "arrow.down.circle").tag(Hub.Page.popular)
                    Label(L("Recently Updated"), systemImage: "clock.arrow.circlepath").tag(Hub.Page.updated)
                    Label(L("Name A–Z"), systemImage: "textformat").tag(Hub.Page.name)
                }
                if !m.categories.isEmpty {
                    Section(L("Categories")) {
                        ForEach(m.categories, id: \.self) { c in
                            Label(L(c), systemImage: "square.grid.2x2").tag(Hub.Page.category(c))
                        }
                    }
                }
                Section(L("Library")) {
                    Label(L("Installed"), systemImage: "checkmark.circle").tag(Hub.Page.installed)
                    Label(L("Updates"), systemImage: "arrow.triangle.2.circlepath").tag(Hub.Page.updates)
                        .badge(m.updates.count)
                }
                Section(L("Create")) {
                    Button { m.comingSoon = .init(title: "Theme Studio", version: "2.1") } label: {
                        Label("Theme Studio", systemImage: "paintbrush.pointed")
                    }
                    Button { m.comingSoon = .init(title: L("Layout Editor"), version: "2.3") } label: {
                        Label(L("Layout Editor"), systemImage: "rectangle.split.3x1")
                    }
                    Button { m.openFolder() } label: {
                        Label(m.kind == .themes ? L("Themes Folder") : L("Layouts Folder"), systemImage: "folder")
                    }
                    Button { m.openGitHub("tree/main/\(m.kind.rawValue)") } label: {
                        Label(m.kind == .themes ? L("Submit a Theme…") : L("Submit a Layout…"), systemImage: "arrow.up.forward.square")
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210)
        } detail: {
            Group {
                switch m.page {
                case .installed: InstalledPage(m: m)
                default: StorePage(m: m)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: Binding(get: { m.kind == .themes ? 0 : 2 }, set: { v in
                        switch v {
                        case 0: m.kind = .themes
                        case 2: m.kind = .layouts
                        default: m.comingSoon = .init(title: L("Widgets"), version: "2.3")
                        }
                        if case .category = m.page { m.page = .featured }
                    })) {
                        Text(L("Themes")).tag(0)
                        Text(L("Widgets")).tag(1)
                        Text(L("Layouts")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .searchable(text: $m.search, prompt: m.kind == .themes ? L("Search Themes") : L("Search Layouts"))
            .onChange(of: m.search) { s in if !s.isEmpty && (m.page == .featured || m.page == .installed) { m.page = .name } }
        }
        .alert(item: $m.comingSoon) { c in
            Alert(title: Text(String(format: L("%@ is in development"), c.title)),
                  message: Text(String(format: L("It's planned for GlassBar %@. You can follow the progress in the roadmap."), c.version)),
                  primaryButton: .default(Text(L("OK"))),
                  secondaryButton: .default(Text(L("Open Roadmap"))) { m.openGitHub("blob/main/ROADMAP.md") })
        }
    }
}

private struct StorePage: View {
    @ObservedObject var m: HubModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !m.message.isEmpty {
                    Text(m.message).font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                switch m.storeState {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding(60)
                case .failed:
                    VStack(spacing: 10) {
                        Text(L("The store couldn't be reached. Check your connection and try again.")).foregroundStyle(.secondary)
                        Button(L("Try Again")) { m.loadStore(force: true) }
                    }
                    .frame(maxWidth: .infinity).padding(60)
                case .loaded:
                    if m.page == .featured && m.search.isEmpty {
                        if m.kind == .layouts {
                            Text(L("A layout replaces GlassBar's buttons for one app with your own: shortcuts, menu commands, links. Write one as JSON, the guide is docs/LAYOUTS.md on GitHub."))
                                .foregroundStyle(.secondary)
                        }
                        if let f = m.featured { Hero(m: m, item: f) }
                        Shelf(m: m, title: m.kind == .themes ? L("New Themes") : L("New Layouts"), items: Array(m.items(.new).prefix(4))) { m.page = .new }
                        if !m.installs.isEmpty {
                            Shelf(m: m, title: L("Most Installed"), items: Array(m.items(.popular).prefix(4))) { m.page = .popular }
                        }
                        ForEach(m.categories, id: \.self) { c in
                            Shelf(m: m, title: L(c), items: Array(m.items(.category(c)).prefix(4))) { m.page = .category(c) }
                        }
                    } else {
                        Text(title).font(.largeTitle.bold())
                        let list = m.items(m.page)
                        if list.isEmpty {
                            Text(m.page == .updates ? L("Everything is up to date.") : L("Nothing here yet.")).foregroundStyle(.secondary)
                        }
                        ItemGrid(m: m, items: list)
                    }
                }
            }
            .padding(24)
        }
    }

    private var title: String {
        if !m.search.isEmpty { return String(format: L("Results for “%@”"), m.search) }
        switch m.page {
        case .new: return L("New")
        case .popular: return L("Most Installed")
        case .updated: return L("Recently Updated")
        case .name: return L("Name A–Z")
        case .category(let c): return L(c)
        case .updates: return L("Updates")
        default: return L("Featured")
        }
    }
}

private struct Hero: View {
    @ObservedObject var m: HubModel
    let item: StoreItem

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.kind == .themes ? L("FEATURED THEME") : L("FEATURED LAYOUT")).font(.caption.bold()).tracking(1).foregroundStyle(.white.opacity(0.7))
                Text(item.name).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                if !item.description.isEmpty { Text(item.description).foregroundStyle(.white.opacity(0.8)) }
                HStack(spacing: 12) {
                    GetButton(m: m, item: item, prominent: true)
                    Text(byline(item, m)).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            Spacer(minLength: 0)
            BarCrop(image: m.preview(item), fraction: m.kind == .themes ? 0.32 : 0.36, fromLeft: m.kind == .layouts)
                .frame(maxWidth: 560)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
        }
        .padding(32)
        .frame(minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x22252E), Color(hex: 0x0D0E12)], startPoint: .leading, endPoint: .trailing))
        )
    }
}

private struct Shelf: View {
    @ObservedObject var m: HubModel
    let title: String
    let items: [StoreItem]
    let seeAll: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title2.bold())
                    Spacer()
                    Button(L("See All"), action: seeAll).buttonStyle(.link)
                }
                ItemGrid(m: m, items: items)
            }
        }
    }
}

private struct ItemGrid: View {
    @ObservedObject var m: HubModel
    let items: [StoreItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], alignment: .leading, spacing: 20) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Stage { BarCrop(image: m.preview(item), fraction: m.kind == .themes ? 0.22 : 0.27, fromLeft: m.kind == .layouts) }
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline).lineLimit(1)
                            Text(byline(item, m)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        GetButton(m: m, item: item, prominent: false)
                    }
                }
                .help(item.description)
            }
        }
    }
}

private func byline(_ item: StoreItem, _ m: HubModel) -> String {
    var parts = [item.category.isEmpty ? "" : L(item.category), item.author].filter { !$0.isEmpty }
    if let n = m.installCount(item), n > 0 { parts.append(String(format: L("%d installs"), n)) }
    return parts.joined(separator: " · ")
}

private struct GetButton: View {
    @ObservedObject var m: HubModel
    let item: StoreItem
    let prominent: Bool
    @EnvironmentObject var d: AppState

    var body: some View {
        let version = m.installedVersion(item)
        if m.busy.contains(m.kind.rawValue + "/" + item.id) {
            ProgressView().controlSize(.small).frame(width: 60)
        } else if let version, version >= item.version {
            if m.kind == .layouts {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("Installed")).frame(width: 60)
            } else if let t = m.installedTheme(item), d.theme.id != t.id {
                pill(L("Apply")) { m.apply(t) }
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("In Use")).frame(width: 60)
            }
        } else {
            pill(version == nil ? L("Get") : L("Update")) { m.get(item) }
        }
    }

    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(minWidth: 44).padding(.horizontal, 10).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.black : Color.accentColor)
        .background(Capsule().fill(prominent ? Color.white : Color.primary.opacity(0.1)))
    }
}

/// A dark card behind a bar preview.
private struct Stage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x2C2E35)))
    }
}

/// Part of a bar screenshot: the right end for themes (the Control Strip shows a theme best), the left for layouts
/// (where the app's buttons are). The full bar is far too wide for a card.
private struct BarCrop: View {
    let image: NSImage?
    /// how much of the bar's width
    let fraction: CGFloat
    var fromLeft = false

    var body: some View {
        if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = CGFloat(cg.width) * fraction
            let crop = cg.cropping(to: CGRect(x: fromLeft ? 0 : CGFloat(cg.width) - w, y: 0, width: w, height: CGFloat(cg.height)))
            if let crop {
                Image(decorative: crop, scale: 1).resizable().interpolation(.high)
                    .aspectRatio(w / CGFloat(cg.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color.black).aspectRatio(9, contentMode: .fit)
        }
    }
}

private struct InstalledPage: View {
    @ObservedObject var m: HubModel
    @EnvironmentObject var d: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Installed")).font(.largeTitle.bold())
                    Spacer()
                    Button(m.kind == .themes ? L("Open Themes Folder") : L("Open Layouts Folder")) { m.openFolder() }
                    Button(L("Reload")) { m.refreshLocal(); d.theme = ThemeStore.shared.theme(id: d.theme.id) ?? .classic }
                }
                Text(m.kind == .themes ? L("Write your own theme as JSON in the themes folder. The guide is in docs/THEMES.md on GitHub.")
                                       : L("Write your own layout as JSON in the layouts folder. The guide is in docs/LAYOUTS.md on GitHub."))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], alignment: .leading, spacing: 20) {
                    if m.kind == .themes {
                        ForEach(m.themes) { t in themeCard(t) }
                    } else {
                        ForEach(m.layouts) { l in layoutCard(l) }
                    }
                }
                if m.kind == .layouts && m.layouts.isEmpty { Text(L("No layouts installed yet.")).foregroundStyle(.secondary) }
            }
            .padding(24)
        }
    }

    private func themeCard(_ t: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Stage {
                if let i = m.previews["local:themes:" + t.id] { BarCrop(image: i, fraction: 0.22) } else { Swatch(theme: t) }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.displayName).font(.headline).lineLimit(1)
                    Text(t.isBuiltIn ? L("Built in") : t.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if d.theme.id == t.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("In Use"))
                } else {
                    Button(L("Apply")) { m.apply(t) }
                }
                if !t.isBuiltIn {
                    Menu {
                        Button(L("Show in Finder")) { m.reveal(ThemeStore.shared.locations[t.id]) }
                        Button(L("Move to Trash"), role: .destructive) { m.delete(t) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
    }

    private func layoutCard(_ l: BarLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Stage { BarCrop(image: m.previews["local:layouts:" + l.id], fraction: 0.27, fromLeft: true) }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.name).font(.headline).lineLimit(1)
                    Text(appNames(l)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    Button(L("Show in Finder")) { m.reveal(LayoutStore.shared.locations[l.id]) }
                    Button(L("Move to Trash"), role: .destructive) { m.delete(l) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    private func appNames(_ l: BarLayout) -> String {
        l.apps.map { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) } ?? id
        }
        .map { $0.replacingOccurrences(of: ".app", with: "") }
        .joined(separator: ", ")
    }
}

/// For a theme without a screenshot: a few buttons in its colors on its bar color.
private struct Swatch: View {
    let theme: Theme

    var body: some View {
        let l = theme.layer(nil), active = theme.layer(.active)
        HStack(spacing: 4) {
            ForEach(Array(["<", "☀︎", "vol", "mute", "siri"].enumerated()), id: \.offset) { i, s in
                let layer = i == 3 ? active : l
                let r = min(theme.isSkin ? layer.radius : theme.cornerRadius, 9)
                Text(theme.cased(s)).font(theme.font(9)).foregroundStyle(layer.text)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: r).fill(theme.isSkin ? (layer.fill ?? .clear) : theme.glassTint.opacity(0.2)))
                    .overlay(RoundedRectangle(cornerRadius: r)
                        .strokeBorder(layer.borderColor, lineWidth: theme.isSkin && layer.border != "none" ? 1 : 0))
            }
        }
        .padding(4)
        .background(theme.color(theme.skin?.bar?.fill) ?? .black)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
