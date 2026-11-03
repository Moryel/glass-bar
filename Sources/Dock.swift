import AppKit
import SwiftUI

// The Dock widget's data: pinned apps and recents from the Dock's own preferences, running apps from NSWorkspace,
// badges read from the Dock's Accessibility tree. Nothing runs until the widget is shown for the first time.

struct DockApp: Identifiable, Equatable {
    /// bundle id, or the path for apps without one
    let id: String
    let url: URL
    let name: String
}

final class DockModel: ObservableObject {
    static let shared = DockModel()

    @Published private(set) var pinned: [DockApp] = []
    @Published private(set) var recents: [DockApp] = []
    @Published private(set) var running: [DockApp] = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var badges: [String: String] = [:]
    /// the Dock's own "Show suggested and recent apps"
    private(set) var dockShowsRecents = true

    private var isStarted = false
    private var observers: [Any] = []
    private var axObserver: AXObserver?
    private var reloadItem: DispatchWorkItem?
    private var badgeTimer: Timer?
    private var visibleCount = 0
    /// path → bundle id, used on the work queue only
    private var idCache: [String: String] = [:]

    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadPreferences()
        loadRunning()
        observeDock()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let self else { return }
                self.loadRunning()
                if (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.dock" {
                    self.observeDock()
                }
                self.scheduleReload(preferences: false)
            })
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.loadHidden() })
        }
        // a badge often changes right after its app was used
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReload(preferences: false)
        })
    }

    /// The Dock posts no Accessibility notification when a badge changes, only when items come and go. While the widget
    /// is on the bar the badges are read again every 10 s (one IPC round trip per item, off the main thread).
    func setVisible(_ isVisible: Bool) {
        start()
        visibleCount = max(0, visibleCount + (isVisible ? 1 : -1))
        if visibleCount > 0, badgeTimer == nil {
            readBadges()
            let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.readBadges() }
            t.tolerance = 3
            RunLoop.main.add(t, forMode: .common)
            badgeTimer = t
        } else if visibleCount == 0 {
            badgeTimer?.invalidate()
            badgeTimer = nil
        }
    }

    func items(_ content: DockContent, order: [String]) -> [DockApp] {
        var l: [DockApp]
        switch content {
        case .dock: l = pinned + running.filter { a in !pinned.contains { $0.id == a.id } }
        case .running: l = running
        case .pinned: l = pinned
        }
        // custom order: the reordered apps swap among their own slots, the rest keep their Dock position
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let slots = l.indices.filter { rank[l[$0].id] != nil }
        let sorted = slots.map { l[$0] }.sorted { rank[$0.id]! < rank[$1.id]! }
        for (slot, a) in zip(slots, sorted) { l[slot] = a }
        return l
    }

    func isRunning(_ a: DockApp) -> Bool { running.contains { $0.id == a.id } }
    func isPinned(_ a: DockApp) -> Bool { pinned.contains { $0.id == a.id } }

    func runningApp(_ a: DockApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { Self.id(of: $0) == a.id }
    }

    // MARK: loading

    private func scheduleReload(preferences: Bool) {
        reloadItem?.cancel()
        let w = DispatchWorkItem { [weak self] in
            if preferences { self?.loadPreferences() }
            self?.readBadges()
        }
        reloadItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private func loadPreferences() {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        func apps(_ key: String) -> [DockApp] {
            let tiles = CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]] ?? []
            return tiles.compactMap { tile in
                let data = tile["tile-data"] as? [String: Any] ?? [:]
                let bundleID = data["bundle-identifier"] as? String
                let file = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String
                guard let url = file.flatMap(URL.init(string:)) ?? bundleID.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
                else { return nil }
                return DockApp(id: bundleID ?? url.path, url: url, name: Self.displayName(url))
            }
        }
        // Finder is always first in the Dock but isn't stored in its preferences
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let p = [DockApp(id: "com.apple.finder", url: finderURL, name: Self.displayName(finderURL))] + apps("persistent-apps"), r = apps("recent-apps")
        dockShowsRecents = CFPreferencesCopyAppValue("show-recents" as CFString, domain) as? Bool ?? true
        if p != pinned { pinned = p }
        if r != recents { recents = r }
    }

    private func loadRunning() {
        let me = Bundle.main.bundleIdentifier
        let l = NSWorkspace.shared.runningApplications.compactMap { a -> DockApp? in
            guard a.activationPolicy == .regular, a.bundleIdentifier != me, let url = a.bundleURL else { return nil }
            return DockApp(id: Self.id(of: a), url: url, name: a.localizedName ?? Self.displayName(url))
        }
        if l != running { running = l }
        loadHidden()
    }

    private func loadHidden() {
        let h = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(Self.id(of:)))
        if h != hidden { hidden = h }
    }

    static func id(of a: NSRunningApplication) -> String { a.bundleIdentifier ?? a.bundleURL?.path ?? "\(a.processIdentifier)" }

    static func displayName(_ url: URL) -> String {
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    // MARK: Accessibility

    private var dockPID: pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier }

    /// Items being added or removed (pinning, a new app) arrive as created/destroyed notifications on the Dock.
    private func observeDock() {
        if let o = axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        axObserver = nil
        guard SystemControl.hasAccessibility, let pid = dockPID else { return }
        var o: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in DockModel.shared.scheduleReload(preferences: true) }, &o) == .success, let o else { return }
        let app = AXUIElementCreateApplication(pid)
        for n in [kAXCreatedNotification, kAXUIElementDestroyedNotification] { AXObserverAddNotification(o, app, n as CFString, nil) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        axObserver = o
    }

    private func readBadges() {
        guard SystemControl.hasAccessibility, let pid = dockPID else { return }
        // permission granted after launch
        if axObserver == nil { observeDock() }
        SystemControl.workQueue.async {
            var b: [String: String] = [:]
            for list in AX.children(AX.appElement(pid)) {
                for item in AX.children(list) {
                    guard let label = AX.attribute(item, "AXStatusLabel") as? String, !label.isEmpty,
                          let url = AX.attribute(item, kAXURLAttribute) as? URL else { continue }
                    b[self.cachedID(url)] = label
                }
            }
            DispatchQueue.main.async { if b != self.badges { self.badges = b } }
        }
    }

    private func cachedID(_ url: URL) -> String {
        if let s = idCache[url.path] { return s }
        let s = Bundle(url: url)?.bundleIdentifier ?? url.path
        idCache[url.path] = s
        return s
    }

    /// The Dock's item for an app (for its own menu: Keep in Dock / Remove from Dock).
    private func dockItem(_ a: DockApp, pid: pid_t) -> AXUIElement? {
        for list in AX.children(AX.appElement(pid)) {
            for item in AX.children(list) {
                if let url = AX.attribute(item, kAXURLAttribute) as? URL, cachedID(url) == a.id { return item }
            }
        }
        return nil
    }

    // MARK: actions

    func open(_ a: DockApp) {
        let c = NSWorkspace.OpenConfiguration()
        c.activates = true
        NSWorkspace.shared.openApplication(at: a.url, configuration: c)
    }

    func tap(_ a: DockApp, frontID: String, behavior: DockFrontTap) {
        guard a.id == frontID, let app = runningApp(a) else { open(a); return }
        switch behavior {
        case .hide: app.hide()
        case .windows: showWindows(app)
        case .nothing: break
        }
    }

    /// App Exposé (⌃↓) for the app.
    func showWindows(_ app: NSRunningApplication) {
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { SystemControl.pressKey(125, [.maskControl, .maskSecondaryFn]) }
    }

    func newWindow(_ a: DockApp) {
        open(a)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let pid = self.runningApp(a)?.processIdentifier else { return }
            SystemControl.workQueue.async {
                if !AX.pressMenuItem(pid, titles: ["New Window", "New Finder Window"]) { SystemControl.pressKey(45, .maskCommand) }
            }
        }
    }

    /// Pinning goes through the Dock's own menu, so the Dock stays the one that writes its preferences.
    func toggleKeepInDock(_ a: DockApp) {
        guard let pid = dockPID else { return }
        let keys = isPinned(a) ? ["REMOVE_FROM_DOCK"] : ["KEEP_IN_DOCK"]
        let dock = Bundle(path: "/System/Library/CoreServices/Dock.app")
        let titles = Set(keys.flatMap { k in
            [k == "KEEP_IN_DOCK" ? "Keep in Dock" : "Remove from Dock", dock?.localizedString(forKey: k, value: nil, table: "DockMenus") ?? ""]
        })
        SystemControl.workQueue.async {
            guard let item = self.dockItem(a, pid: pid) else { return }
            AXUIElementPerformAction(item, "AXShowMenu" as CFString)
            guard let menu = AX.children(item).first(where: { AX.attribute($0, kAXRoleAttribute) as? String == "AXMenu" }) else { return }
            if let target = AX.search(menu, 4, { titles.contains(AX.attribute($0, kAXTitleAttribute) as? String ?? "") }) {
                AXUIElementPerformAction(target, kAXPressAction as CFString)
            } else {
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
        }
    }

    func revealInFinder(_ a: DockApp) { NSWorkspace.shared.activateFileViewerSelecting([a.url]) }
}

// MARK: settings

enum DockContent: String, CaseIterable { case dock, running, pinned }
enum DockFrontTap: String, CaseIterable { case hide, windows, nothing }
enum DockIconStyle: String, CaseIterable { case auto, color, mono, text, pixel }
enum DockIconSize: String, CaseIterable {
    case auto, small, medium, large
    var points: CGFloat? {
        switch self {
        case .auto: nil
        case .small: 16
        case .medium: 20
        case .large: 24
        }
    }
}

enum DockPreset: String, CaseIterable {
    case macOS, running, launcher

    var name: String {
        switch self {
        case .macOS: L("Like macOS Dock")
        case .running: L("Running Apps Only")
        case .launcher: L("Launcher")
        }
    }
}

final class DockSettings: ObservableObject {
    static let shared = DockSettings()

    @Published var content = DockContent(rawValue: Defaults.string("dockContent")) ?? .dock { didSet { Defaults.set("dockContent", content.rawValue) } }
    /// nil follows the Dock's own setting
    @Published var showsRecents = UserDefaults.standard.object(forKey: "dockShowsRecents") as? Bool {
        didSet { UserDefaults.standard.set(showsRecents, forKey: "dockShowsRecents") }
    }
    @Published var showsBadges = Defaults.bool("dockShowsBadges", true) { didSet { Defaults.set("dockShowsBadges", showsBadges) } }
    @Published var showsDots = Defaults.bool("dockShowsDots", true) { didSet { Defaults.set("dockShowsDots", showsDots) } }
    @Published var longPressMenu = Defaults.bool("dockLongPressMenu", true) { didSet { Defaults.set("dockLongPressMenu", longPressMenu) } }
    @Published var frontTap = DockFrontTap(rawValue: Defaults.string("dockFrontTap")) ?? .hide { didSet { Defaults.set("dockFrontTap", frontTap.rawValue) } }
    @Published var iconStyle = DockIconStyle(rawValue: Defaults.string("dockIconStyle")) ?? .auto { didSet { Defaults.set("dockIconStyle", iconStyle.rawValue) } }
    @Published var iconSize = DockIconSize(rawValue: Defaults.string("dockIconSize")) ?? .auto { didSet { Defaults.set("dockIconSize", iconSize.rawValue) } }
    @Published var order = Defaults.stringArray("dockOrder") ?? [] { didSet { Defaults.set("dockOrder", order) } }

    var recentsShown: Bool { showsRecents ?? DockModel.shared.dockShowsRecents }

    var preset: DockPreset? {
        switch (content, showsBadges, showsDots, recentsShown) {
        case (.dock, true, true, _): .macOS
        case (.running, true, _, false): .running
        case (.pinned, false, false, false): .launcher
        default: nil
        }
    }

    func apply(_ p: DockPreset) {
        switch p {
        case .macOS: content = .dock; showsBadges = true; showsDots = true; showsRecents = nil
        case .running: content = .running; showsBadges = true; showsRecents = false
        case .launcher: content = .pinned; showsBadges = false; showsDots = false; showsRecents = false
        }
    }
}

// MARK: icons

enum DockIcons {
    private static var color: [String: NSImage] = [:]
    private static var pixel: [String: NSImage] = [:]

    static func icon(_ url: URL) -> NSImage {
        if let i = color[url.path] { return i }
        // a small bitmap instead of the multi-resolution icon: less memory, cheaper to draw on every bar update
        let i = render(NSWorkspace.shared.icon(forFile: url.path), 64)
        color[url.path] = i
        return i
    }

    /// 16×16, drawn later without interpolation so the pixels stay hard
    static func pixelated(_ url: URL) -> NSImage {
        if let i = pixel[url.path] { return i }
        let i = render(icon(url), 16)
        pixel[url.path] = i
        return i
    }

    private static func render(_ image: NSImage, _ side: Int) -> NSImage {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let i = NSImage(size: NSSize(width: side, height: side))
        i.addRepresentation(rep)
        return i
    }
}
