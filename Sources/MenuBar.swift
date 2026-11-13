import AppKit
import SwiftUI

// The menu bar on the Touch Bar: the front app's menus on the left, the icons from the right of the menu bar after
// them. Everything is read and pressed through Accessibility, and only while the row is on the bar.

/// A menu of the front app, or an icon from the right side of the menu bar.
struct MenuBarEntry: Identifiable {
    let id: String
    var title: String
    /// what the item shows next to its icon: the time, the battery percentage
    var value = ""
    var symbol: String? = nil
    var icon: NSImage? = nil
    var x: CGFloat = 0
    /// nil while the item can't be pressed: in a full-screen app the hidden menu bar gives other apps' icons away by name only
    var element: AXUIElement?
}

/// A line of an open menu.
struct MenuRow: Identifiable {
    let id: Int
    var title = ""
    var shortcut = ""
    var isEnabled = true
    var isChecked = false
    var hasSubmenu = false
    var isSeparator = false
    let element: AXUIElement
}

struct MenuLevel {
    let title: String
    let rows: [MenuRow]
}

enum MenuBarReader {
    /// Other apps answer these queries and a busy one can take its time, so they stay off the queue the buttons use.
    static let queue = DispatchQueue(label: "menubar", qos: .userInitiated)

    static func menus(_ pid: pid_t) -> [MenuBarEntry] {
        guard let bar = AX.element(AX.attribute(AX.appElement(pid), kAXMenuBarAttribute)) else { return [] }
        return AX.children(bar).enumerated().compactMap { i, o in
            guard let t = AX.attribute(o, kAXTitleAttribute) as? String, !t.isEmpty else { return nil }
            return MenuBarEntry(id: "menu\(i)", title: t, symbol: i == 0 && t == "Apple" ? "apple.logo" : nil, element: o)
        }
    }

    /// The items of a menu bar item or of a menu item with a submenu.
    static func rows(_ parent: AXUIElement) -> [MenuRow] {
        guard let menu = AX.children(parent).first else { return [] }
        var rows: [MenuRow] = []
        for (i, o) in AX.children(menu).prefix(80).enumerated() {
            let title = AX.attribute(o, kAXTitleAttribute) as? String ?? ""
            if title.isEmpty {
                // a line between groups; none at the start, never two in a row
                if rows.last.map({ !$0.isSeparator }) == true { rows.append(MenuRow(id: i, isSeparator: true, element: o)) }
                continue
            }
            rows.append(MenuRow(id: i, title: title, shortcut: shortcut(o),
                                isEnabled: AX.attribute(o, kAXEnabledAttribute) as? Bool ?? true,
                                isChecked: !(AX.attribute(o, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty,
                                hasSubmenu: !AX.children(o).isEmpty, element: o))
        }
        if rows.last?.isSeparator == true { rows.removeLast() }
        return rows
    }

    /// "⇧⌘N"
    private static func shortcut(_ o: AXUIElement) -> String {
        guard let c = AX.attribute(o, kAXMenuItemCmdCharAttribute) as? String, !c.isEmpty else { return "" }
        let m = AX.attribute(o, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
        return (m & 4 != 0 ? "⌃" : "") + (m & 2 != 0 ? "⌥" : "") + (m & 1 != 0 ? "⇧" : "") + (m & 8 == 0 ? "⌘" : "") + c.uppercased()
    }

    // MARK: the right side

    private static let agent = "com.apple.MenuBarAgent"
    /// apps that had something in the menu bar the last time every app was asked
    private static var owners = Set<pid_t>()
    private static var lastFullScan = Date.distantPast

    /// Since macOS 26 one process lays the menu bar out and knows who owns each icon. Before that every running app
    /// has to be asked, which takes a few seconds, so that happens at most twice a minute and in between only the
    /// apps known to have an icon are asked again.
    static func extras() -> [MenuBarEntry] {
        let apps = NSWorkspace.shared.runningApplications
        if let a = apps.first(where: { $0.bundleIdentifier == agent }) { return agentExtras(a).sorted { $0.x < $1.x } }
        var l: [MenuBarEntry] = []
        let full = Date().timeIntervalSince(lastFullScan) > 30
        if full { lastFullScan = Date(); owners = [] }
        for app in apps where full || owners.contains(app.processIdentifier) {
            let found = appExtras(app)
            if !found.isEmpty { owners.insert(app.processIdentifier) }
            l += found
        }
        return l.sorted { $0.x < $1.x }
    }

    /// Apple's own items (Wi-Fi, battery, the clock, Control Center) are in the agent itself; for the others it only
    /// names the app, and the item to press comes from that app.
    private static func agentExtras(_ agent: NSRunningApplication) -> [MenuBarEntry] {
        var l: [MenuBarEntry] = []
        for window in AX.children(appElement(agent)) {
            for group in AX.children(window) {
                if let o = AX.search(group, 3, { isMenuExtra($0) }), let id = AX.attribute(o, kAXIdentifierAttribute) as? String {
                    if !l.contains(where: { $0.id == id }) { l.append(system(id, o)) }
                    continue
                }
                guard let owner = AX.children(group).first(where: { AX.attribute($0, kAXRoleAttribute) as? String == "AXApplication" }) else { continue }
                var pid: pid_t = 0
                AXUIElementGetPid(owner, &pid)
                guard let app = NSRunningApplication(processIdentifier: pid), !l.contains(where: { $0.id.hasPrefix(key(app) + "#") }) else { continue }
                var found = appExtras(app)
                if found.isEmpty {
                    found = [look(MenuBarEntry(id: key(app) + "#0", title: AX.attribute(owner, kAXTitleAttribute) as? String ?? "", x: x(group)), app)]
                }
                l += found
            }
        }
        return l
    }

    private static func key(_ app: NSRunningApplication) -> String { app.bundleIdentifier ?? "\(app.processIdentifier)" }

    private static func appExtras(_ app: NSRunningApplication) -> [MenuBarEntry] {
        guard let bar = AX.element(AX.attribute(appElement(app), "AXExtrasMenuBar")) else { return [] }
        return AX.children(bar).enumerated().compactMap { i, o in
            guard AX.attribute(o, kAXRoleAttribute) as? String == "AXMenuBarItem" else { return nil }
            if let id = AX.attribute(o, kAXIdentifierAttribute) as? String, id.hasPrefix("com.apple.menuextra.") { return system(id, o) }
            let title = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { AX.attribute(o, $0) as? String }.first { !$0.isEmpty }
            return look(MenuBarEntry(id: "\(key(app))#\(i)", title: title ?? app.localizedName ?? "", x: x(o), element: o), app)
        }
    }

    private static func look(_ entry: MenuBarEntry, _ app: NSRunningApplication) -> MenuBarEntry {
        var e = entry
        switch key(app) {
        case "com.apple.TextInputMenuAgent": e.symbol = "keyboard"
        case "com.apple.Spotlight", "com.apple.campo": e.symbol = "magnifyingglass"
        case "com.apple.Siri": e.icon = app.icon
        case "com.apple.systemuiserver", "com.apple.controlcenter":
            // these draw for others; the item's name says more than their own icon
            if e.title == "Siri", let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Siri") { e.icon = NSWorkspace.shared.icon(forFile: u.path) }
        default: e.icon = app.icon
        }
        return e
    }

    private static func appElement(_ app: NSRunningApplication) -> AXUIElement {
        let e = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(e, 0.2)
        return e
    }

    private static func isMenuExtra(_ o: AXUIElement) -> Bool {
        AX.attribute(o, kAXRoleAttribute) as? String == "AXMenuBarItem"
            && (AX.attribute(o, kAXIdentifierAttribute) as? String)?.hasPrefix("com.apple.menuextra.") == true
    }

    private static func x(_ o: AXUIElement) -> CGFloat {
        var p = CGPoint.zero
        if let v = AX.attribute(o, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        return p.x
    }

    private static func system(_ id: String, _ o: AXUIElement) -> MenuBarEntry {
        let name = id.replacingOccurrences(of: "com.apple.menuextra.", with: "").lowercased()
        let value = AX.attribute(o, kAXValueAttribute) as? String ?? ""
        // the clock is its own text; the others get a symbol, or their name when there is none for them
        return MenuBarEntry(id: id, title: AX.attribute(o, kAXDescriptionAttribute) as? String ?? name, value: value.trimmingCharacters(in: .whitespaces),
                            symbol: name == "clock" ? nil : symbols.first { name.contains($0.0) }?.1, x: x(o), element: o)
    }

    private static let symbols: [(String, String)] = [
        ("wifi", "wifi"), ("battery", "battery.75"), ("controlcenter", "switch.2"), ("now-playing", "play.circle"),
        ("sound", "speaker.wave.2.fill"), ("volume", "speaker.wave.2.fill"), ("focus", "moon.fill"), ("display", "display"),
        ("textinput", "keyboard"), ("spotlight", "magnifyingglass"), ("user", "person.crop.circle"),
        ("timemachine", "clock.arrow.circlepath"), ("vpn", "network"), ("mirroring", "airplayvideo"), ("airplay", "airplayvideo"),
        ("keyboardbrightness", "light.max"), ("accessibility", "accessibility"), ("hearing", "ear"), ("weather", "cloud.sun"),
    ]
}

extension AppState {
    /// The menu bar as a panel over the bar, from the widget's button.
    func showMenuBar() {
        menuPath = []
        panel = .menuBar
    }

    /// The row calls this as it appears and disappears; the menu bar is only read in between.
    func setMenuBarVisible(_ visible: Bool) {
        menuBarTimer?.invalidate()
        menuBarTimer = nil
        guard visible else { menuPath = []; return }
        refreshMenuBar()
        // the clock and the battery change, and apps add and remove their icons
        let t = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshMenuBar(menus: false) }
        t.tolerance = 1
        menuBarTimer = t
    }

    var isMenuBarVisible: Bool { menuBarTimer != nil }

    func refreshMenuBar(menus: Bool = true) {
        guard SystemControl.hasAccessibility else { return }
        let pid = frontApp?.processIdentifier
        MenuBarReader.queue.async {
            let m = menus ? pid.map(MenuBarReader.menus) : nil
            if let m { DispatchQueue.main.async { self.menuBarMenus = m } }
            let e = MenuBarReader.extras()
            DispatchQueue.main.async { self.menuBarExtras = e }
        }
    }

    func openMenu(_ title: String, _ element: AXUIElement?) {
        guard let element else { return }
        MenuBarReader.queue.async {
            let rows = MenuBarReader.rows(element)
            DispatchQueue.main.async { if !rows.isEmpty { self.menuPath.append(MenuLevel(title: title, rows: rows)) } }
        }
    }

    func press(_ r: MenuRow) {
        guard !isPreview else { return }
        if r.hasSubmenu { openMenu(r.title, r.element); return }
        menuPath = []
        MenuBarReader.queue.async { AXUIElementPerformAction(r.element, kAXPressAction as CFString) }
    }

    /// Opens the item's own menu or window under the menu bar, as a click on it would.
    func press(_ e: MenuBarEntry) {
        guard !isPreview, let o = e.element else { return }
        MenuBarReader.queue.async { AXUIElementPerformAction(o, kAXPressAction as CFString) }
    }
}

struct MenuBarRow: View {
    @ObservedObject var d: AppState
    var isClosable = false

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            if let level = d.menuPath.last {
                GlassButton("chevron.left", width: Metrics.narrowWidth) { d.menuPath.removeLast() }
                ScrollingStrip {
                    Text(level.title).font(.bar(12, .semibold)).foregroundStyle(d.theme.barText.opacity(0.55)).lineLimit(1).padding(.horizontal, 4)
                    ForEach(level.rows) { r in
                        if r.isSeparator { line } else { row(r) }
                    }
                }
                .id(d.menuPath.count)
            } else {
                if isClosable { GlassButton("xmark", width: Metrics.narrowWidth, action: d.collapse) }
                if !SystemControl.hasAccessibility {
                    Text(L("The menu bar needs Accessibility: System Settings → Privacy & Security → Accessibility"))
                        .font(.bar(12)).foregroundStyle(d.theme.barText.opacity(0.5)).padding(.leading, 6)
                    Spacer(minLength: 0)
                } else {
                    ScrollingStrip {
                        ForEach(d.menuBarMenus) { m in
                            GlassButton(width: nil, action: { d.openMenu(m.title, m.element) }) {
                                if let s = m.symbol { Icon(s) } else { BarText(verbatim: m.title) }
                            }
                            .inScrollingStrip()
                        }
                        if !d.menuBarMenus.isEmpty && !d.menuBarExtras.isEmpty { line }
                        ForEach(d.menuBarExtras) { e in
                            GlassButton(width: nil, action: { d.press(e) }) { label(e).opacity(e.element == nil ? 0.35 : 1) }.inScrollingStrip()
                                .allowsHitTesting(e.element != nil)
                        }
                    }
                }
            }
        }
        .onAppear { d.setMenuBarVisible(true) }
        .onDisappear { d.setMenuBarVisible(false) }
    }

    private var line: some View {
        Rectangle().fill(d.theme.barText.opacity(0.22)).frame(width: 1, height: 16).padding(.horizontal, 3)
    }

    private func row(_ r: MenuRow) -> some View {
        GlassButton(width: nil, highlight: r.isChecked ? .active : nil, action: { d.press(r) }) {
            HStack(spacing: 5) {
                BarText(verbatim: r.title)
                if r.hasSubmenu {
                    Icon("chevron.right").scaleEffect(0.7)
                } else if !r.shortcut.isEmpty {
                    Text(r.shortcut).font(.bar(10)).opacity(0.5)
                }
            }
            .opacity(r.isEnabled ? 1 : 0.35)
        }
        .inScrollingStrip()
        .allowsHitTesting(r.isEnabled)
    }

    @ViewBuilder private func label(_ e: MenuBarEntry) -> some View {
        HStack(spacing: 4) {
            if let i = e.icon {
                Image(nsImage: i).resizable().interpolation(.high).frame(width: 20, height: 20)
            } else if let s = e.symbol {
                Icon(s)
            } else if e.value.isEmpty {
                BarText(verbatim: e.title.count > 14 ? String(e.title.prefix(13)) + "…" : e.title)
            }
            if !e.value.isEmpty { BarText(verbatim: e.value, tabular: true) }
        }
    }
}
