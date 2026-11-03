import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Appearance theme ("Theme" in the menu). A theme without a skin uses one of the two glass styles plus colors and strengths.
/// Classic: pronounced glass, bright highlight, light ring. Minimal: Liquid Glass close to macOS 26; light refracting at the edge,
/// glass thickening toward the edge, no ring. A theme with a skin (`Skin.swift`) draws every part its own way: terminal, pixel art…
/// Built-in glass themes live in code; the others are .glasstheme packages (a folder with theme.json, fonts, images, sounds)
/// or single JSON files. Missing keys take their default, so old files keep working when keys are added.
struct Theme: Codable, Equatable, Identifiable {
    enum Style: String, Codable, CaseIterable { case classic, minimal }
    enum FontDesign: String, Codable, CaseIterable { case standard, rounded, monospaced, serif }
    enum FontWeight: String, Codable, CaseIterable { case regular, medium, semibold, bold }

    var id: String
    var name: String
    var author = ""
    var version = 1
    var style = Style.classic
    /// glass fill color (#RRGGBB)
    var glassColor = "#FFFFFF"
    /// strengths; 1 is the built-in look
    var glass = 1.0
    var edge = 1.0
    var glow = 1.0
    var shadow = 1.0
    var bounce = 1.0
    /// corner radius of buttons; 13 or more is a capsule
    var cornerRadius = 13.0
    var textColor = "#FFFFFF"
    /// tint of the primary action (+ in Safari); empty for none
    var accent = ""
    /// filled part of sliders; empty keeps each slider's own color
    var sliderColor = ""
    var fontDesign = FontDesign.standard
    var fontWeight = FontWeight.medium
    /// Backdrop raw value applied with the theme; empty leaves the user's background
    var backdrop = ""
    /// per-role looks ("active", "primary", "accent", "operator", "suggestions"); glass themes use only `fill`
    var roles: [String: LayerPatch] = [:]
    var skin: Skin? = nil
    /// folder of a package theme (its fonts, images and sounds); not saved
    var baseURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, author, version, style, glassColor, glass, edge, glow, shadow, bounce, cornerRadius, textColor, accent,
             sliderColor, fontDesign, fontWeight, backdrop, roles, skin
    }

    static let classic = Theme(id: "classic", name: "Classic")
    static let minimal = Theme(id: "minimal", name: "Minimal Liquid Glass", style: .minimal, accent: "#0A84FF")
    static let graphite = Theme(id: "graphite", name: "Graphite", glass: 0.7, edge: 0.6, glow: 0.5, shadow: 1.3, bounce: 0.5,
                                cornerRadius: 6, fontWeight: .semibold)
    static let neon = Theme(id: "neon", name: "Neon", style: .minimal, glassColor: "#4DE8FF", glass: 1.5, edge: 1.6, glow: 1.6,
                            textColor: "#E8FDFF", accent: "#FF3EA5", sliderColor: "#4DE8FF", fontDesign: .rounded)
    static let builtIns = [classic, minimal, graphite, neon]

    /// The theme on the bar, for views that are drawn outside the environment (fonts in `Font.bar`).
    static var current = Theme.classic

    var isBuiltIn: Bool { Theme.builtIns.contains { $0.id == id } || ThemeStore.bundledIDs.contains(id) }
    var displayName: String { isBuiltIn ? L(name) : name }

    var isMinimal: Bool { style == .minimal }
    var glassTint: Color { Color(hexString: glassColor) ?? .white }
    var text: Color { Color(hexString: textColor) ?? .white }
    var accentColor: Color? { Color(hexString: accent) }
    var sliderFill: Color? { Color(hexString: sliderColor) }
    /// radius for a shape of the given height (capsule at most)
    func radius(_ height: CGFloat) -> CGFloat { min(CGFloat(skin != nil ? layer(nil).radius : cornerRadius), height / 2) }
    func shape(_ height: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius(height), style: .continuous) }

    var design: Font.Design {
        switch fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }

    var weight: Font.Weight {
        if let w = skin?.text?.weight { return Font.Weight(name: w) }
        switch fontWeight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    /// Highlight color of a role in the glass styles.
    func glassColor(_ role: Role) -> Color? {
        if let k = role.key, let c = Color(hexString: roles[k]?.fill ?? "") { return c }
        switch role {
        case .active: return .white.opacity(0.28)
        case .primary: return Color(hex: 0x0A84FF, 0.6)
        case .accent: return accentColor
        case .operatorKey: return Color(hex: 0xFF9F0A, 0.5)
        case .suggestions: return Color(hex: 0x2A3A50)
        case .custom(let c): return c
        }
    }
}

extension Theme {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var t = Theme(id: try c.decode(String.self, forKey: .id), name: (try? c.decode(String.self, forKey: .name)) ?? "")
        func read<T: Decodable>(_ k: CodingKeys, _ p: WritableKeyPath<Theme, T>) {
            guard c.contains(k) else { return }
            do { t[keyPath: p] = try c.decode(T.self, forKey: k) } catch { SystemControl.log("theme \(t.id): \(k.stringValue) ignored: \(error.short)") }
        }
        read(.author, \.author); read(.version, \.version); read(.style, \.style); read(.glassColor, \.glassColor)
        read(.glass, \.glass); read(.edge, \.edge); read(.glow, \.glow); read(.shadow, \.shadow); read(.bounce, \.bounce)
        read(.cornerRadius, \.cornerRadius); read(.textColor, \.textColor); read(.accent, \.accent); read(.sliderColor, \.sliderColor)
        read(.fontDesign, \.fontDesign); read(.fontWeight, \.fontWeight); read(.backdrop, \.backdrop); read(.roles, \.roles)
        if c.contains(.skin) {
            do { t.skin = try c.decode(Skin.self, forKey: .skin) } catch { SystemControl.log("theme \(t.id): skin ignored: \(error.short)") }
        }
        self = t
    }
}

/// A part of a bar that a theme can style on its own. Built-in bars use roles instead of fixed colors.
enum Role: Equatable {
    /// selected or switched on (mute, the current space, the chosen tab)
    case active
    /// the main action (Done, Send, a correction)
    case primary
    /// the theme's accent (+ in Safari); none in themes without one
    case accent
    /// Calculator's ÷ × − + =
    case operatorKey
    /// the typing suggestions group
    case suggestions
    /// a fixed color that no role covers (Night Shift)
    case custom(Color)

    var key: String? {
        switch self {
        case .active: "active"
        case .primary: "primary"
        case .accent: "accent"
        case .operatorKey: "operator"
        case .suggestions: "suggestions"
        case .custom: nil
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.classic
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    /// "#RRGGBB" or "#RRGGBBAA"; nil when empty or invalid
    init?(hexString s: String) {
        let h = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 || h.count == 8, let v = UInt32(h, radix: 16) else { return nil }
        if h.count == 8 { self.init(hex: v >> 8, Double(v & 0xFF) / 255) } else { self.init(hex: v) }
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let v = { (x: CGFloat) in Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(c.redComponent), v(c.greenComponent), v(c.blueComponent))
    }
}

extension Font.Weight {
    init(name: String) {
        switch name {
        case "regular": self = .regular
        case "semibold": self = .semibold
        case "bold": self = .bold
        case "heavy": self = .heavy
        default: self = .medium
        }
    }
}

extension UTType {
    static let glassTheme = UTType(exportedAs: "com.yukselozge.glasstheme", conformingTo: .package)
}

/// Theme and layout ids name their folder on disk and come from downloaded files: nothing that could leave it.
func isSafeID(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 100 && !id.hasPrefix(".") && !id.contains("..")
        && !id.contains { $0 == "/" || $0 == "\\" || $0 == ":" || $0 == "\0" || $0.isNewline }
}

/// A file named in a theme or layout (image, font, sound). Symlinks and "../" can't reach outside the package.
func packageFile(_ base: URL, _ name: String) -> URL? {
    let root = base.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    let u = base.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
    return u.path.hasPrefix(root) ? u : nil
}

/// Built-in and installed themes.
final class ThemeStore {
    static let shared = ThemeStore()
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GlassBar/Themes", isDirectory: true)
    /// package themes that ship inside the app (Resources/Themes)
    static let bundledFolder = Bundle.main.resourceURL?.appendingPathComponent("Themes", isDirectory: true)
    static let bundledIDs = Set(bundledFolder.map(loadAll)?.map(\.id) ?? [])
    private(set) var bundled: [Theme] = []
    private(set) var userThemes: [Theme] = []
    /// where each user theme was loaded from (its package folder or file)
    private(set) var locations: [String: URL] = [:]
    var all: [Theme] { Theme.builtIns + bundled + userThemes }

    private init() { reload() }

    func reload() {
        bundled = ThemeStore.bundledFolder.map(ThemeStore.loadAll) ?? []
        let found = ThemeStore.entries(folder).compactMap { u in (try? ThemeStore.load(u)).map { ($0, u) } }.filter { !$0.0.isBuiltIn }
        userThemes = found.map(\.0).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        locations = Dictionary(found.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
    }

    private static func entries(_ folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    /// Every theme in a folder: .glasstheme packages (folders), .glasstheme files, and plain folders with a theme.json.
    private static func loadAll(_ folder: URL) -> [Theme] { entries(folder).compactMap { try? load($0) } }

    static func load(_ url: URL) throws -> Theme {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let file = isFolder.boolValue ? url.appendingPathComponent("theme.json") : url
        guard isFolder.boolValue || url.pathExtension == "glasstheme" || url.pathExtension == "json" else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var t: Theme
        do { t = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file)) } catch {
            SystemControl.log("theme \(url.lastPathComponent): could not read it: \(error.short)")
            throw error
        }
        if isFolder.boolValue { t.baseURL = url }
        let name = url.lastPathComponent
        t.check { SystemControl.log("theme \(name): \($0)") }
        return t
    }

    func theme(id: String) -> Theme? { all.first { $0.id == id } }

    func encode(_ t: Theme) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(t)
    }

    private func target(_ id: String) -> URL { folder.appendingPathComponent(id + ".glasstheme") }

    /// Writes a theme to the themes folder. A package theme keeps its files: they are copied over when it moves
    /// (a built-in package saved as a copy) and theme.json is rewritten.
    @discardableResult func save(_ t: Theme) throws -> Theme {
        guard isSafeID(t.id) else {
            SystemControl.log("theme \(t.id): id can't be used as a file name, not saved")
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var t = t
        let to = target(t.id)
        if let from = t.baseURL {
            if from.standardizedFileURL != to.standardizedFileURL {
                try? fm.removeItem(at: to)
                try fm.copyItem(at: from, to: to)
            }
            try encode(t).write(to: to.appendingPathComponent("theme.json"), options: .atomic)
            t.baseURL = to
        } else {
            try encode(t).write(to: to, options: .atomic)
        }
        reload()
        return t
    }

    /// Writes a theme where the user chose: a package folder with its files, or a single file.
    func export(_ t: Theme, to url: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        if let from = t.baseURL {
            try fm.copyItem(at: from, to: url)
            try encode(t).write(to: url.appendingPathComponent("theme.json"), options: .atomic)
        } else {
            try encode(t).write(to: url, options: .atomic)
        }
    }

    /// Moves a user theme to the Trash.
    func delete(_ id: String) {
        guard let u = locations[id] ?? (isSafeID(id) ? target(id) : nil) else { return }
        try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
        reload()
    }

    /// The screenshot of the bar that comes with a theme: preview.png in its package, or Resources/Previews for the glass themes.
    func preview(_ t: Theme) -> URL? {
        let candidates = [t.baseURL?.appendingPathComponent("preview.png"),
                          Bundle.main.resourceURL?.appendingPathComponent("Previews/\(t.id).png")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A new id from the name ("My Theme" → "my-theme-3fa2").
    static func newID(_ name: String) -> String {
        let slug = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "theme" : String(slug.prefix(30))) + "-" + UUID().uuidString.prefix(4).lowercased()
    }

    /// Installs a .glasstheme package or file; a theme with a built-in's id gets a new id.
    @discardableResult func install(_ url: URL) throws -> Theme {
        var t = try ThemeStore.load(url)
        if t.isBuiltIn { t.id = ThemeStore.newID(t.name) }
        if t.name.isEmpty { t.name = url.deletingPathExtension().lastPathComponent }
        return try save(t)
    }
}

// MARK: checking values

/// Values that parse but would break the bar (a text scale of 0 hides every label) are clamped or dropped here,
/// one log line each, so a theme author can see what was ignored.
extension Theme {
    mutating func check(_ log: (String) -> Void) {
        func color(_ s: inout String, _ key: String, _ fallback: String, emptyOK: Bool = false) {
            if emptyOK && s.isEmpty { return }
            if Color(hexString: s) == nil { log("\(key) \"\(s)\" is not a hex color, using \(fallback.isEmpty ? "none" : fallback)"); s = fallback }
        }
        func clamp(_ v: inout Double, _ key: String, _ r: ClosedRange<Double>) {
            let c = v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound
            if c != v { log("\(key) \(v) is out of range \(r.lowerBound)...\(r.upperBound), using \(c)"); v = c }
        }
        if id.trimmingCharacters(in: .whitespaces).isEmpty { id = ThemeStore.newID(name); log("empty id, using \(id)") }
        color(&glassColor, "glassColor", "#FFFFFF")
        color(&textColor, "textColor", "#FFFFFF")
        color(&accent, "accent", "", emptyOK: true)
        color(&sliderColor, "sliderColor", "", emptyOK: true)
        clamp(&glass, "glass", 0...2.5); clamp(&edge, "edge", 0...2.5); clamp(&glow, "glow", 0...2.5)
        clamp(&shadow, "shadow", 0...2); clamp(&bounce, "bounce", 0...2)
        clamp(&cornerRadius, "cornerRadius", 0...100)
        if !backdrop.isEmpty && Backdrop(rawValue: backdrop) == nil { log("unknown backdrop \"\(backdrop)\", ignored"); backdrop = "" }
        for (k, var p) in roles {
            if Role.keys.contains(k) { p.check("roles.\(k)", log); roles[k] = p } else { log("unknown role \"\(k)\", ignored"); roles[k] = nil }
        }
        skin?.check(baseURL, log)
    }
}

extension Error {
    /// "skin.text.scale: expected Double" instead of the whole DecodingError dump
    var short: String {
        guard let e = self as? DecodingError else { return localizedDescription }
        func path(_ c: DecodingError.Context) -> String { c.codingPath.map(\.stringValue).joined(separator: ".") }
        switch e {
        case .typeMismatch(let t, let c): return "\(path(c)): expected \(t)"
        case .valueNotFound(let t, let c): return "\(path(c)): expected \(t)"
        case .keyNotFound(let k, _): return "missing \"\(k.stringValue)\""
        case .dataCorrupted(let c):
            let detail = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? c.debugDescription
            return path(c).isEmpty ? "not valid JSON (\(detail))" : "\(path(c)): \(detail)"
        @unknown default: return "\(e)"
        }
    }
}

extension Role {
    static let keys: Set = ["active", "primary", "accent", "operator", "suggestions"]
}

extension LayerPatch {
    static let borders: Set = ["none", "solid", "dashed", "pixel", "ascii", "sketch"]

    mutating func check(_ at: String, _ log: (String) -> Void) {
        func color(_ v: inout String?, _ key: String, noneOK: Bool = false) {
            guard let s = v, !(noneOK && s == "none"), Color(hexString: s) == nil else { return }
            log("\(at).\(key) \"\(s)\" is not a hex color, ignored"); v = nil
        }
        func clamp(_ v: inout Double?, _ key: String, _ r: ClosedRange<Double>) {
            guard let x = v else { return }
            let c = x.isFinite ? min(max(x, r.lowerBound), r.upperBound) : r.lowerBound
            if c != x { log("\(at).\(key) \(x) is out of range \(r.lowerBound)...\(r.upperBound), using \(c)"); v = c }
        }
        color(&fill, "fill", noneOK: true); color(&fill2, "fill2"); color(&text, "text")
        color(&borderColor, "borderColor"); color(&glowColor, "glowColor")
        if let b = border, !LayerPatch.borders.contains(b) { log("\(at).border \"\(b)\" is unknown, ignored"); border = nil }
        clamp(&borderWidth, "borderWidth", 0...6); clamp(&radius, "radius", 0...100)
        clamp(&glow, "glow", 0...12); clamp(&shadow, "shadow", 0...4)
        if let c = chars, c.trimmingCharacters(in: .whitespaces).isEmpty { log("\(at).chars is empty, using \"[ ]\""); chars = "[ ]" }
    }
}

extension Skin {
    mutating func check(_ base: URL?, _ log: (String) -> Void) {
        let fm = FileManager.default
        func exists(_ file: String) -> Bool { base.flatMap { packageFile($0, file) }.map { fm.fileExists(atPath: $0.path) } ?? false }
        button?.check("skin.button", log); pressed?.check("skin.pressed", log); group?.check("skin.group", log)
        bar?.check(log)
        text?.check(base, exists, log)
        if let p = press, PressEffect(rawValue: p) == nil { log("skin.press \"\(p)\" is unknown, ignored"); press = nil }
        if let i = icons {
            icons = i.filter { k, v in
                if v.isEmpty { log("skin.icons.\(k) is empty, ignored"); return false }
                if v.hasPrefix("image:"), !exists(String(v.dropFirst(6))) { log("skin.icons.\(k): \(v.dropFirst(6)) not found, ignored"); return false }
                return true
            }
        }
        if let s = sounds {
            sounds = s.filter { k, v in
                if ["click", "blip", "tick"].contains(v) || exists(v) { return true }
                log("skin.sounds.\(k): \(v) not found, ignored"); return false
            }
        }
    }
}

extension BarStyle {
    mutating func check(_ log: (String) -> Void) {
        for (k, p) in [("fill", \BarStyle.fill), ("fill2", \.fill2), ("patternColor", \.patternColor)] {
            if let s = self[keyPath: p], Color(hexString: s) == nil { log("skin.bar.\(k) \"\(s)\" is not a hex color, ignored"); self[keyPath: p] = nil }
        }
        if let p = pattern, !["stars", "grid", "none"].contains(p) { log("skin.bar.pattern \"\(p)\" is unknown, ignored"); pattern = nil }
        if let o = overlay, !["scanlines", "none"].contains(o) { log("skin.bar.overlay \"\(o)\" is unknown, ignored"); overlay = nil }
    }
}

extension TextStyle {
    mutating func check(_ base: URL?, _ exists: (String) -> Bool, _ log: (String) -> Void) {
        if let s = scale {
            let c = s.isFinite ? min(max(s, 0.5), 2) : 1
            if c != s { log("skin.text.scale \(s) is out of range 0.5...2, using \(c)"); scale = c }
        }
        if let t = tracking, !t.isFinite || abs(t) > 6 { log("skin.text.tracking \(t) is out of range -6...6, ignored"); tracking = nil }
        if let w = weight, !["regular", "medium", "semibold", "bold", "heavy"].contains(w) { log("skin.text.weight \"\(w)\" is unknown, ignored"); weight = nil }
        if let c = letterCase, !["upper", "lower", "none"].contains(c) { log("skin.text.case \"\(c)\" is unknown, ignored"); letterCase = nil }
        if let f = font, !f.isEmpty, !["system", "mono", "rounded", "serif"].contains(f) {
            let isFile = f.hasSuffix(".ttf") || f.hasSuffix(".otf")
            if isFile ? !exists(f) : NSFont(name: f, size: 12) == nil { log("skin.text.font \(f) not found, using the system font"); font = nil }
        }
    }
}
