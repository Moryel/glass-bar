import AppKit
import SwiftUI

/// A layout replaces the app area of the bar for the apps it names. It's written as JSON (layout.json in a folder,
/// or a single .json file) in ~/Library/Application Support/GlassBar/Layouts; the theme still decides how it looks.
struct BarLayout: Codable, Identifiable, Equatable {
    var id: String
    var name = ""
    var author = ""
    var version = 1
    var description = ""
    /// bundle identifiers ("com.apple.dt.Xcode")
    var apps: [String] = []
    var items: [LayoutItem] = []
    /// folder of a package layout (its images); not saved
    var baseURL: URL? = nil

    enum CodingKeys: String, CodingKey { case id, name, author, version, description, apps, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        author = (try? c.decode(String.self, forKey: .author)) ?? ""
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        if let one = try? c.decode(String.self, forKey: .apps) { apps = [one] } else { apps = (try? c.decode([String].self, forKey: .apps)) ?? [] }
        items = try c.decode([LayoutItem].self, forKey: .items)
    }
}

struct LayoutItem: Codable, Equatable {
    /// button (the default), group, space, text, widget
    var type: String? = nil
    /// for a widget: clock, battery, cpu, memory, worldClock, clipboard, nowPlaying, dock
    var widget: String? = nil
    /// for the world clock: a time zone ("Asia/Tokyo")
    var option: String? = nil
    var label: String? = nil
    /// an Apple symbol name, or "image:file.png" from the layout's folder
    var icon: String? = nil
    /// active, primary, accent, operator: drawn with the theme's role
    var role: String? = nil
    var width: Double? = nil
    var action: LayoutAction? = nil
    /// the buttons of a group
    var items: [LayoutItem]? = nil
}

struct LayoutAction: Codable, Equatable {
    /// "cmd+shift+b", "f5", "ctrl+`"
    var shortcut: String? = nil
    /// a menu item's title in the front app ("Show Sidebar")
    var menu: String? = nil
    /// a link, or an app's bundle identifier
    var open: String? = nil
}

// MARK: actions

enum KeyNames {
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
        "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
        "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111,
    ]

    /// "cmd+shift+b" → key code, flags and the character (for finding ⌘ shortcuts in the menu); nil if it can't be read
    static func parse(_ s: String) -> (CGKeyCode, CGEventFlags, String?)? {
        var flags: CGEventFlags = []
        var key: String?
        for part in s.lowercased().split(separator: "+", omittingEmptySubsequences: false).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "alt", "option", "opt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "": break
            default: key = part
            }
        }
        guard let key, let code = codes[key] else { return nil }
        return (code, flags, key.count == 1 ? key : nil)
    }
}

extension AppState {
    func run(_ a: LayoutAction?) {
        guard let a else { return }
        if let s = a.shortcut, let (code, flags, character) = KeyNames.parse(s) {
            shortcut(code, flags, character)
        } else if let m = a.menu {
            menu(nil, m)
        } else if let o = a.open {
            if o.contains("://"), let u = URL(string: o) {
                NSWorkspace.shared.open(u)
            } else if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: o) {
                NSWorkspace.shared.openApplication(at: u, configuration: .init())
            }
        }
    }
}

// MARK: store

/// Installed layouts. The first one (by name) that names the front app is used.
final class LayoutStore {
    static let shared = LayoutStore()
    let folder = Edition.supportFolder.appendingPathComponent("Layouts", isDirectory: true)
    private(set) var all: [BarLayout] = []
    private(set) var locations: [String: URL] = [:]
    private var byApp: [String: BarLayout] = [:]

    private init() { reload() }

    func reload() {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let found = entries.compactMap { u in (try? LayoutStore.load(u)).map { ($0, u) } }
            .sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
        all = found.map(\.0)
        locations = Dictionary(found.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
        byApp = [:]
        for l in all {
            for app in l.apps {
                if let other = byApp[app] { SystemControl.log("layout \(l.id): \(app) already has \(other.id), skipped for it") } else { byApp[app] = l }
            }
        }
    }

    func layout(for bundleID: String) -> BarLayout? { byApp[bundleID] }

    static func load(_ url: URL) throws -> BarLayout {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        guard isFolder.boolValue || url.pathExtension == "json" else { throw CocoaError(.fileReadUnsupportedScheme) }
        let file = isFolder.boolValue ? url.appendingPathComponent("layout.json") : url
        var l: BarLayout
        do { l = try JSONDecoder().decode(BarLayout.self, from: Data(contentsOf: file)) } catch {
            SystemControl.log("layout \(url.lastPathComponent): could not read it: \(error.short)")
            throw error
        }
        if isFolder.boolValue { l.baseURL = url }
        let name = url.lastPathComponent
        l.check { SystemControl.log("layout \(name): \($0)") }
        return l
    }

    /// Copies a layout folder into the layouts folder (replacing an older copy).
    @discardableResult func install(_ url: URL) throws -> BarLayout {
        let l = try LayoutStore.load(url)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let old = locations[l.id] { try? fm.trashItem(at: old, resultingItemURL: nil) }
        let to = folder.appendingPathComponent(l.id, isDirectory: true)
        try? fm.removeItem(at: to)
        try fm.copyItem(at: url, to: to)
        reload()
        return l
    }

    func delete(_ id: String) {
        if let u = locations[id] { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        reload()
    }

    func preview(_ l: BarLayout) -> URL? {
        guard let u = l.baseURL?.appendingPathComponent("preview.png"), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
}

extension BarLayout {
    /// Like themes: what can't work is dropped with one log line, so a broken layout never breaks the bar.
    mutating func check(_ log: (String) -> Void) {
        if apps.isEmpty { log("no \"apps\", the layout won't show anywhere") }
        let base = baseURL
        func fix(_ list: [LayoutItem], _ at: String) -> [LayoutItem] {
            list.enumerated().compactMap { i, item in
                var item = item
                let here = "\(at)[\(i)]"
                let type = item.type ?? "button"
                guard ["button", "group", "space", "text", "widget"].contains(type) else { log("\(here): unknown type \"\(type)\", skipped"); return nil }
                if let r = item.role, !Role.keys.contains(r) { log("\(here): unknown role \"\(r)\", ignored"); item.role = nil }
                if let w = item.width, !(20...400).contains(w) { log("\(here): width \(w) is out of range 20...400, ignored"); item.width = nil }
                if let icon = item.icon, icon.hasPrefix("image:") {
                    let file = String(icon.dropFirst(6))
                    if base.map({ !FileManager.default.fileExists(atPath: $0.appendingPathComponent(file).path) }) ?? true {
                        log("\(here): \(file) not found, icon ignored"); item.icon = nil
                    }
                }
                if let s = item.action?.shortcut, KeyNames.parse(s) == nil { log("\(here): can't read the shortcut \"\(s)\""); item.action?.shortcut = nil }
                if type == "widget" && WidgetKind(rawValue: item.widget ?? "") == nil {
                    log("\(here): unknown widget \"\(item.widget ?? "")\", skipped"); return nil
                }
                if type == "button" && item.label == nil && item.icon == nil { log("\(here): a button needs a label or an icon, skipped"); return nil }
                if type == "group" {
                    item.items = fix(item.items ?? [], here + ".items")
                    if item.items?.isEmpty ?? true { log("\(here): empty group, skipped"); return nil }
                }
                return item
            }
        }
        items = fix(items, "items")
    }
}

// MARK: drawing

/// The app area drawn from a layout.
struct LayoutBar: View {
    @ObservedObject var d: AppState
    let layout: BarLayout
    @Environment(\.theme) private var theme

    var body: some View {
        ForEach(Array(layout.items.enumerated()), id: \.offset) { _, item in
            switch item.type ?? "button" {
            case "space": Spacer(minLength: 0)
            case "widget":
                if let k = WidgetKind(rawValue: item.widget ?? "") { WidgetView(d: d, kind: k, option: item.option) }
            case "text":
                Text(item.label ?? "").font(.bar(12, .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).padding(.horizontal, 4)
            case "group":
                ButtonGroup(buttons: (item.items ?? []).map { b in
                    GroupButton(symbol: b.label == nil ? b.icon : nil, text: b.label, highlight: role(b.role), isVerbatim: true) { d.run(b.action) }
                }, buttonWidth: item.width.map { CGFloat($0) } ?? groupWidth(item.items ?? []))
            default:
                GlassButton(width: item.width.map { CGFloat($0) } ?? (item.label == nil ? Metrics.iconWidth : nil),
                            highlight: role(item.role), action: { d.run(item.action) }) {
                    HStack(spacing: 5) {
                        if let icon = item.icon { LayoutIcon(name: icon, base: layout.baseURL) }
                        if let label = item.label { BarText(verbatim: label).padding(.horizontal, 6) }
                    }
                }
            }
        }
    }

    /// A group doesn't stretch: its buttons are as wide as the widest label, or narrow for icons.
    private func groupWidth(_ items: [LayoutItem]) -> CGFloat {
        let font = theme.nsFont(13, .medium)
        let widest = items.compactMap(\.label).map { (theme.cased($0) as NSString).size(withAttributes: [.font: font]).width }.max()
        return widest.map { ceil($0) + 24 } ?? Metrics.narrowWidth
    }

    private func role(_ s: String?) -> Role? { Role.named(s) }
}

private struct LayoutIcon: View {
    let name: String
    let base: URL?

    var body: some View {
        if name.hasPrefix("image:"), let base, let i = NSImage(contentsOf: base.appendingPathComponent(String(name.dropFirst(6)))) {
            Image(nsImage: i).resizable().aspectRatio(contentMode: .fit).frame(height: 16)
        } else {
            Icon(name)
        }
    }
}
