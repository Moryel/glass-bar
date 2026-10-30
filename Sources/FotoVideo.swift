import AppKit

// Fotoğraflar'da açık video: oynatıcının sarma çubuğu ve süreleri Erişilebilirlik ile okunur, sarma çubuğa yazılarak
// yapılır. Küçük resimler için video Fotoğraflar'dan geçici klasöre aktarılır (AppleScript; ilk kullanımda Otomasyon izni).
struct FotoVideo: Equatable {
    var konum: Float
    var gecen: String
    var kalan: String
    /// hangi video (değişince küçük resimler yeniden çıkarılır): "28 Eki 2026 18:51, Süre 1:40" gibi
    var kimlik: String
}

enum FotoOynatici {
    static let paket = "com.apple.Photos"

    private static func tuval(_ pid: pid_t) -> AXUIElement? {
        guard let w = AX.deger(AX.uygulama(pid), kAXFocusedWindowAttribute) else { return nil }
        return AX.ara(w as! AXUIElement, 6) { AX.deger($0, kAXIdentifierAttribute) as? String == "IPXCanvasItemView" }
    }

    private static func cubuk(_ tuval: AXUIElement) -> AXUIElement? {
        AX.cocuklar(tuval).first { AX.deger($0, kAXIdentifierAttribute) as? String == "slider_scrubber" }
    }

    /// "01:16", "‎−00:24", "1:02:03" → saniye
    private static func saniye(_ s: String) -> Double {
        s.filter { $0.isNumber || $0 == ":" }.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    /// Arka kuyrukta çağrılır. Video açık değilse nil.
    static func oku(_ pid: pid_t) -> FotoVideo? {
        guard let t = tuval(pid), cubuk(t) != nil else { return nil }
        let c = AX.cocuklar(t)
        let yazilar = c.filter { AX.deger($0, kAXRoleAttribute) as? String == "AXStaticText" }
            .compactMap { AX.deger($0, kAXValueAttribute) as? String }
        guard yazilar.count >= 2 else { return nil }
        let kimlik = c.compactMap { o -> String? in
            guard AX.deger(o, kAXRoleAttribute) as? String == "AXGroup" else { return nil }
            return AX.deger(o, kAXDescriptionAttribute) as? String
        }.first ?? ""
        let g = saniye(yazilar[0]), k = saniye(yazilar[1])
        return FotoVideo(konum: g + k > 0 ? Float(g / (g + k)) : 0, gecen: yazilar[0], kalan: yazilar[1], kimlik: kimlik)
    }

    /// Videoyu 0…1 arasındaki yere sarar.
    static func sar(_ pid: pid_t, _ oran: Float) {
        guard let t = tuval(pid), let s = cubuk(t) else { return }
        let sonuc = AXUIElementSetAttributeValue(s, kAXValueAttribute as CFString, NSNumber(value: Double(oran)))
        if sonuc != .success { Sistem.gunluk("foto sarma: \(sonuc.rawValue)") }
    }

    static func oynatDuraklat(_ pid: pid_t) { AX.pencereDugmesi(pid, "button_playPause") }

    /// Seçili videoyu geçici klasöre aktarır, dosyanın yolunu döner. Arka kuyrukta çağrılır.
    static func disaAktar() -> String? {
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("TouchBar2-foto")
        try? FileManager.default.removeItem(at: klasor)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        Sistem.betik("""
        tell application "Photos"
            set s to selection
            if (count s) = 0 then return
            export {item 1 of s} to (POSIX file "\(klasor.path)")
        end tell
        """)
        let dosyalar = (try? FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil)) ?? []
        return dosyalar.first { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }?.path
    }
}
