import AppKit

// Driving the front app's menus and window buttons through Accessibility (called on the work queue).
// Menu items are found by their language-independent identifier (Mail, Messages) or by their Turkish title.
enum AX {
    static func appElement(_ pid: pid_t) -> AXUIElement {
        let u = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(u, 0.6)
        return u
    }

    static func attribute(_ o: AXUIElement, _ k: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, k as CFString, &v) == .success ? v : nil
    }

    static func children(_ o: AXUIElement) -> [AXUIElement] { attribute(o, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    /// Depth-first search.
    static func search(_ o: AXUIElement, _ depth: Int, _ predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        if predicate(o) { return o }
        guard depth > 0 else { return nil }
        for c in children(o) { if let b = search(c, depth - 1, predicate) { return b } }
        return nil
    }

    /// Trailing ellipses and colons are dropped so titles like "Taşı…" and "Şuraya Taşı:" compare equal.
    private static func minimal(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "…:. ")).lowercased()
    }

    /// English menu titles: on an English system, an item not found by its Turkish title is found by this one.
    /// (Mail, Messages, Dictation and Photos buttons use language-independent identifiers and are not listed here.)
    static let englishTitles: [String: String] = [
        "Yapılacaklar Listesi": "Checklist", "Ana Başlık": "Title", "Başlık": "Heading", "Alt Başlık": "Subheading",
        "Gövde": "Body", "Madde İşaretli Liste": "Bulleted List", "Tire İşaretli Liste": "Dashed List",
        "Numaralı Liste": "Numbered List", "Yeni Not": "New Note", "Sil": "Delete",
        "Paylaş…": "Share…", "Paylaş": "Share", "Kartı Paylaş…": "Share Card…", "Kartı Paylaş": "Share Card",
        "İşaretleme Araç Çubuğunu Göster": "Show Markup Toolbar", "İşaretleme Araç Çubuğunu Gizle": "Hide Markup Toolbar",
        "Renk Ayarla…": "Adjust Color…", "Boyutu Ayarla…": "Adjust Size…",
        "Sola Döndür": "Rotate Left", "Sağa Döndür": "Rotate Right",
        "Yatay Olarak Çevir": "Flip Horizontal", "Düşey Olarak Çevir": "Flip Vertical",
        "Sola Hizala": "Align Left", "Ortala": "Center", "Sağa Hizala": "Align Right", "İki Yana Yasla": "Justify",
        "Servisler": "Services", "Gönder": "Send", "Dosya Ekle…": "Attach Files…",
        "Sıradaki Olarak Çal": "Play Next", "Gün": "Day", "Hafta": "Week", "Ay": "Month", "Yıl": "Year",
    ]

    static func menuItem(_ pid: pid_t, identifier: String?, titles: [String]) -> AXUIElement? {
        guard let menuBar = attribute(appElement(pid), kAXMenuBarAttribute) else { return nil }
        let wantedTitles = Set((titles + titles.compactMap { englishTitles[$0] }).map(minimal))
        return search(menuBar as! AXUIElement, 7) { o in
            guard attribute(o, kAXRoleAttribute) as? String == "AXMenuItem" else { return false }
            let id = attribute(o, kAXIdentifierAttribute) as? String ?? ""
            if let identifier { return id == identifier }
            // keep the Window menu's "Center" (zoom) apart from text alignment
            guard id != "_zoomCenter:", let t = attribute(o, kAXTitleAttribute) as? String else { return false }
            return wantedTitles.contains(minimal(t))
        }
    }

    @discardableResult
    static func pressMenuItem(_ pid: pid_t, identifier: String? = nil, titles: [String] = []) -> Bool {
        guard let o = menuItem(pid, identifier: identifier, titles: titles),
              attribute(o, kAXEnabledAttribute) as? Bool ?? true else { return false }
        return AXUIElementPerformAction(o, kAXPressAction as CFString) == .success
    }

    /// Whether the menu item has a check mark (the selected view in Calendar).
    static func isChecked(_ pid: pid_t, _ title: String) -> Bool {
        guard let o = menuItem(pid, identifier: nil, titles: [title]) else { return false }
        return !(attribute(o, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty
    }

    /// Titles of the enabled items in a menu item's submenu (Mail "Move to:", "Flag", Services).
    static func submenuTitles(_ pid: pid_t, identifier: String?, titles: [String]) -> [String] {
        guard let o = menuItem(pid, identifier: identifier, titles: titles), let menu = children(o).first else { return [] }
        return children(menu).compactMap { c in
            guard let t = attribute(c, kAXTitleAttribute) as? String, !t.isEmpty,
                  attribute(c, kAXEnabledAttribute) as? Bool ?? true else { return nil }
            return t
        }
    }

    @discardableResult
    static func pressSubmenuItem(_ pid: pid_t, identifier: String?, titles: [String], _ itemTitle: String) -> Bool {
        guard let o = menuItem(pid, identifier: identifier, titles: titles), let menu = children(o).first,
              let c = children(menu).first(where: { attribute($0, kAXTitleAttribute) as? String == itemTitle }) else { return false }
        return AXUIElementPerformAction(c, kAXPressAction as CFString) == .success
    }

    /// Presses a button in the front window by its identifier (Calculator: "Add", "Negate"…).
    @discardableResult
    static func pressWindowButton(_ pid: pid_t, _ identifier: String) -> Bool {
        guard let w = attribute(appElement(pid), kAXFocusedWindowAttribute),
              let b = search(w as! AXUIElement, 7, { attribute($0, kAXIdentifierAttribute) as? String == identifier }) else { return false }
        return AXUIElementPerformAction(b, kAXPressAction as CFString) == .success
    }
}
