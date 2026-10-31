import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Appearance theme ("Theme" in the menu): one of the two glass styles plus colors and strengths.
/// Classic: pronounced glass, bright highlight, light ring. Minimal: Liquid Glass close to macOS 26; light refracting at the edge,
/// glass thickening toward the edge, no ring. Built-in themes live in code; user themes are .glasstheme files (JSON) in
/// ~/Library/Application Support/GlassBar/Themes. Missing keys take their default, so old files keep working when keys are added.
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

    static let classic = Theme(id: "classic", name: "Classic")
    static let minimal = Theme(id: "minimal", name: "Minimal Liquid Glass", style: .minimal, accent: "#0A84FF")
    static let graphite = Theme(id: "graphite", name: "Graphite", glass: 0.7, edge: 0.6, glow: 0.5, shadow: 1.3, bounce: 0.5,
                                cornerRadius: 6, fontWeight: .semibold)
    static let neon = Theme(id: "neon", name: "Neon", style: .minimal, glassColor: "#4DE8FF", glass: 1.5, edge: 1.6, glow: 1.6,
                            textColor: "#E8FDFF", accent: "#FF3EA5", sliderColor: "#4DE8FF", fontDesign: .rounded)
    static let builtIns = [classic, minimal, graphite, neon]

    var isBuiltIn: Bool { Theme.builtIns.contains { $0.id == id } }
    var displayName: String { isBuiltIn ? L(name) : name }

    var isMinimal: Bool { style == .minimal }
    var glassTint: Color { Color(hexString: glassColor) ?? .white }
    var text: Color { Color(hexString: textColor) ?? .white }
    var accentColor: Color? { Color(hexString: accent) }
    var sliderFill: Color? { Color(hexString: sliderColor) }
    /// radius for a shape of the given height (capsule at most)
    func radius(_ height: CGFloat) -> CGFloat { min(CGFloat(cornerRadius), height / 2) }
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
        switch fontWeight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
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
        read(.fontDesign, \.fontDesign); read(.fontWeight, \.fontWeight); read(.backdrop, \.backdrop)
        self = t
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
    /// "#RRGGBB"; nil when empty or invalid
    init?(hexString s: String) {
        let h = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let v = { (x: CGFloat) in Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(c.redComponent), v(c.greenComponent), v(c.blueComponent))
    }
}

extension UTType {
    static let glassTheme = UTType(exportedAs: "com.yukselozge.glasstheme", conformingTo: .json)
}

/// Built-in and installed themes.
final class ThemeStore {
    static let shared = ThemeStore()
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GlassBar/Themes", isDirectory: true)
    private(set) var userThemes: [Theme] = []
    var all: [Theme] { Theme.builtIns + userThemes }

    private init() { reload() }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        userThemes = files.filter { $0.pathExtension == "glasstheme" }
            .compactMap { try? decode(Data(contentsOf: $0)) }
            .filter { !$0.isBuiltIn }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func theme(id: String) -> Theme? { all.first { $0.id == id } }

    private func decode(_ data: Data) throws -> Theme { try JSONDecoder().decode(Theme.self, from: data) }

    func encode(_ t: Theme) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(t)
    }

    private func file(_ id: String) -> URL { folder.appendingPathComponent(id + ".glasstheme") }

    func save(_ t: Theme) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encode(t).write(to: file(t.id), options: .atomic)
        reload()
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
        reload()
    }

    /// A new id from the name ("My Theme" → "my-theme-3fa2").
    static func newID(_ name: String) -> String {
        let slug = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "theme" : String(slug.prefix(30))) + "-" + UUID().uuidString.prefix(4).lowercased()
    }

    /// Installs a .glasstheme file; a theme with a built-in's id gets a new id.
    @discardableResult func install(_ url: URL) throws -> Theme {
        var t = try decode(Data(contentsOf: url))
        if t.isBuiltIn { t.id = ThemeStore.newID(t.name) }
        if t.name.isEmpty { t.name = url.deletingPathExtension().lastPathComponent }
        try save(t)
        return t
    }
}
