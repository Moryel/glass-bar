import AppKit

// Öndeki uygulamanın menülerini ve pencere düğmelerini Erişilebilirlik ile kullanma (arka kuyrukta çağrılır).
// Menü öğesi dilden bağımsız kimliğiyle (Mail, Mesajlar) ya da Türkçe başlığıyla bulunur.
enum AX {
    static func uygulama(_ pid: pid_t) -> AXUIElement {
        let u = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(u, 0.6)
        return u
    }

    static func deger(_ o: AXUIElement, _ k: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, k as CFString, &v) == .success ? v : nil
    }

    static func cocuklar(_ o: AXUIElement) -> [AXUIElement] { deger(o, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    /// Derinlik öncelikli arama.
    static func ara(_ o: AXUIElement, _ derinlik: Int, _ kosul: (AXUIElement) -> Bool) -> AXUIElement? {
        if kosul(o) { return o }
        guard derinlik > 0 else { return nil }
        for c in cocuklar(o) { if let b = ara(c, derinlik - 1, kosul) { return b } }
        return nil
    }

    /// "Taşı…", "Şuraya Taşı:" gibi başlıkları karşılaştırmak için sondaki üç nokta ve iki nokta atılır.
    private static func sade(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "…:. ")).lowercased()
    }

    /// Menü başlıklarının İngilizcesi: sistem İngilizceyse Türkçe başlıkla bulunamayan öğe bununla bulunur.
    /// (Mail, Mesajlar, Dikte ve Fotoğraflar'ın düğmeleri dilden bağımsız kimlikle çalışır, burada yok.)
    static let ingilizce: [String: String] = [
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

    static func menuOgesi(_ pid: pid_t, kimlik: String?, basliklar: [String]) -> AXUIElement? {
        guard let cubuk = deger(uygulama(pid), kAXMenuBarAttribute) else { return nil }
        let aranan = Set((basliklar + basliklar.compactMap { ingilizce[$0] }).map(sade))
        return ara(cubuk as! AXUIElement, 7) { o in
            guard deger(o, kAXRoleAttribute) as? String == "AXMenuItem" else { return false }
            let id = deger(o, kAXIdentifierAttribute) as? String ?? ""
            if let kimlik { return id == kimlik }
            // pencere menüsündeki "Ortala" (yakınlaştırma) metin hizalamasıyla karışmasın
            guard id != "_zoomCenter:", let t = deger(o, kAXTitleAttribute) as? String else { return false }
            return aranan.contains(sade(t))
        }
    }

    @discardableResult
    static func menuKomut(_ pid: pid_t, kimlik: String? = nil, basliklar: [String] = []) -> Bool {
        guard let o = menuOgesi(pid, kimlik: kimlik, basliklar: basliklar),
              deger(o, kAXEnabledAttribute) as? Bool ?? true else { return false }
        return AXUIElementPerformAction(o, kAXPressAction as CFString) == .success
    }

    /// Menü öğesinin yanında onay işareti var mı (Takvim'de seçili görünüm).
    static func isaretli(_ pid: pid_t, _ baslik: String) -> Bool {
        guard let o = menuOgesi(pid, kimlik: nil, basliklar: [baslik]) else { return false }
        return !(deger(o, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty
    }

    /// Bir menü öğesinin alt menüsündeki etkin öğelerin başlıkları (Mail "Şuraya Taşı:", "Bayrak", Servisler).
    static func altMenu(_ pid: pid_t, kimlik: String?, basliklar: [String]) -> [String] {
        guard let o = menuOgesi(pid, kimlik: kimlik, basliklar: basliklar), let menu = cocuklar(o).first else { return [] }
        return cocuklar(menu).compactMap { c in
            guard let t = deger(c, kAXTitleAttribute) as? String, !t.isEmpty,
                  deger(c, kAXEnabledAttribute) as? Bool ?? true else { return nil }
            return t
        }
    }

    @discardableResult
    static func altMenuSec(_ pid: pid_t, kimlik: String?, basliklar: [String], _ oge: String) -> Bool {
        guard let o = menuOgesi(pid, kimlik: kimlik, basliklar: basliklar), let menu = cocuklar(o).first,
              let c = cocuklar(menu).first(where: { deger($0, kAXTitleAttribute) as? String == oge }) else { return false }
        return AXUIElementPerformAction(c, kAXPressAction as CFString) == .success
    }

    /// Öndeki penceredeki düğmeye kimliğiyle basar (Hesap Makinesi: "Add", "Negate"…).
    @discardableResult
    static func pencereDugmesi(_ pid: pid_t, _ kimlik: String) -> Bool {
        guard let w = deger(uygulama(pid), kAXFocusedWindowAttribute),
              let b = ara(w as! AXUIElement, 7, { deger($0, kAXIdentifierAttribute) as? String == kimlik }) else { return false }
        return AXUIElementPerformAction(b, kAXPressAction as CFString) == .success
    }
}
