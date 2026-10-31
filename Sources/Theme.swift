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
            if let v = try? c.decode(T.self, forKey: k) { t[keyPath: p] = v }
        }
        read(.author, \.author); read(.version, \.version); read(.style, \.style); read(.glassColor, \.glassColor)
        read(.glass, \.glass); read(.edge, \.edge); read(.glow, \.glow); read(.shadow, \.shadow); read(.bounce, \.bounce)
        read(.cornerRadius, \.cornerRadius); read(.textColor, \.textColor); read(.accent, \.accent); read(.sliderColor, \.sliderColor)
        read(.fontDesign, \.fontDesign); read(.fontWeight, \.fontWeight); read(.backdrop, \.backdrop); read(.roles, \.roles)
        if let s = try? c.decode(Skin.self, forKey: .skin) { t.skin = s }
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
    var all: [Theme] { Theme.builtIns + bundled + userThemes }

    private init() { reload() }

    func reload() {
        bundled = ThemeStore.bundledFolder.map(ThemeStore.loadAll) ?? []
        userThemes = ThemeStore.loadAll(folder).filter { !$0.isBuiltIn }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every theme in a folder: .glasstheme packages (folders), .glasstheme files, and plain folders with a theme.json.
    private static func loadAll(_ folder: URL) -> [Theme] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { try? load($0) }
    }

    static func load(_ url: URL) throws -> Theme {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        if isFolder.boolValue {
            var t = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url.appendingPathComponent("theme.json")))
            t.baseURL = url
            return t
        }
        guard url.pathExtension == "glasstheme" || url.pathExtension == "json" else { throw CocoaError(.fileReadUnsupportedScheme) }
        return try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
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

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: target(id))
        reload()
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
