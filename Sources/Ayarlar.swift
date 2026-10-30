import AppKit
import Carbon

/// GlassBar'ın kendi yazıları: anahtar Türkçe metnin kendisi, çevirisi <dil>.lproj/Localizable.strings'te.
/// Çevirisi olmayan (posta kutusu adı gibi) metin olduğu gibi döner.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

// Orijinaldeki Klavye → Touch Bar Ayarları ve Control Strip özelleştirmesinin karşılığı.
enum Gosterim: String, CaseIterable {
    case uygulama, genis, fTuslari, alanlar, hizliEylem

    var ad: String { L(adTr) }

    private var adTr: String {
        switch self {
        case .uygulama: "Uygulama denetimleri"
        case .genis: "Genişletilmiş Control Strip"
        case .fTuslari: "F1, F2 vb. tuşlar"
        case .alanlar: "Masaüstü alanları"
        case .hizliEylem: "Hızlı Eylemler"
        }
    }
}

/// Daraltılmış Control Strip'e konabilen tuşlar (orijinal "Control Strip'i Özelleştir" listesinden).
enum SeritTusu: String, CaseIterable {
    case parlaklik, ses, sessiz, oynat, siri, missionControl, launchpad, spotlight, bildirim,
         nightShift, ekranResmi, girisKaynagi, masaustu, ekranKoruyucu, kilitle, uyut, klavye, dikte, hizliEylem

    var ad: String { L(adTr) }

    private var adTr: String {
        switch self {
        case .parlaklik: "Parlaklık"
        case .ses: "Ses"
        case .sessiz: "Sessiz"
        case .oynat: "Oynat/Duraklat"
        case .siri: "Siri"
        case .missionControl: "Mission Control"
        case .launchpad: "Uygulamalar"
        case .spotlight: "Spotlight"
        case .bildirim: "Bildirim Merkezi"
        case .nightShift: "Night Shift"
        case .ekranResmi: "Ekran Resmi"
        case .girisKaynagi: "Giriş Kaynakları"
        case .masaustu: "Masaüstünü Göster"
        case .ekranKoruyucu: "Ekran Koruyucu"
        case .kilitle: "Ekranı Kilitle"
        case .uyut: "Uyut"
        case .klavye: "Klavye Aydınlatması"
        case .dikte: "Dikte"
        case .hizliEylem: "Hızlı Eylemler"
        }
    }

    var simge: String {
        switch self {
        case .parlaklik: "sun.max.fill"
        case .ses: "speaker.wave.2.fill"
        case .sessiz: "speaker.slash.fill"
        case .oynat: "playpause.fill"
        case .siri: "circle"
        case .missionControl: "rectangle.3.group"
        case .launchpad: "square.grid.3x3.fill"
        case .spotlight: "magnifyingglass"
        case .bildirim: "list.bullet.rectangle"
        case .nightShift: "moon.stars.fill"
        case .ekranResmi: "camera.viewfinder"
        case .girisKaynagi: "globe"
        case .masaustu: "menubar.dock.rectangle"
        case .ekranKoruyucu: "sparkles.tv"
        case .kilitle: "lock.fill"
        case .uyut: "powersleep"
        case .klavye: "light.max"
        case .dikte: "mic.fill"
        case .hizliEylem: "gearshape.2"
        }
    }

    static let varsayilan: [SeritTusu] = [.parlaklik, .ses, .sessiz, .siri]
    static let enFazla = 5
}

/// UserDefaults'a kısa erişim.
enum Kayit {
    static func yazi(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
    static func dizi(_ k: String) -> [String]? { UserDefaults.standard.stringArray(forKey: k) }
    static func evet(_ k: String, _ v: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? v }
    static func yaz(_ k: String, _ v: Any) { UserDefaults.standard.set(v, forKey: k) }
}

// MARK: Control Strip tuşlarının sistem işleri
enum NightShift {
    private static let istemci: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let sinif = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return sinif.init()
    }()

    /// CBBlueLightStatus: { BOOL active; BOOL enabled; … }
    static var acik: Bool {
        get {
            let sel = NSSelectorFromString("getBlueLightStatus:")
            guard let i = istemci, i.responds(to: sel) else { return false }
            var tampon = [UInt8](repeating: 0, count: 64)
            typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
            _ = tampon.withUnsafeMutableBytes { unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, $0.baseAddress!) }
            return tampon[1] != 0
        }
        set {
            let sel = NSSelectorFromString("setEnabled:")
            guard let i = istemci, i.responds(to: sel) else { return }
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Bool
            _ = unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, newValue)
        }
    }
}

enum GirisKaynagi {
    private static var liste: [TISInputSource] {
        let suzgec = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        return TISCreateInputSourceList(suzgec, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func ozellik(_ s: TISInputSource, _ k: CFString) -> AnyObject? {
        guard let p = TISGetInputSourceProperty(s, k) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
    }

    private static func kimlik(_ s: TISInputSource) -> String { ozellik(s, kTISPropertyInputSourceID) as? String ?? "" }

    /// Şimdiki klavyenin kısa adı: "TR", "ABC" gibi.
    static var kisaAd: String {
        let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if kimlik(s).hasSuffix(".ABC") || kimlik(s).hasSuffix(".US") { return "ABC" }
        if let diller = ozellik(s, kTISPropertyInputSourceLanguages) as? [String], let dil = diller.first {
            return dil.prefix(2).uppercased()
        }
        return "⌨︎"
    }

    /// Şimdiki klavye düzeninde bu tuşun ürettiği karakter (Türkçe Q'da 33 → "ğ"). macOS menü kısayollarını
    /// düzene göre yeniden adlandırdığı için (⌘[ → ⌘Ğ) menüde bu karakterle aranır.
    static func karakter(_ kod: CGKeyCode) -> String? {
        let kaynak = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let p = TISGetInputSourceProperty(kaynak, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let veri = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue() as Data
        var olu: UInt32 = 0
        var uzunluk = 0
        var harfler = [UniChar](repeating: 0, count: 4)
        let sonuc = veri.withUnsafeBytes { b -> OSStatus in
            UCKeyTranslate(b.bindMemory(to: UCKeyboardLayout.self).baseAddress!, kod, UInt16(kUCKeyActionDown), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &olu, 4, &uzunluk, &harfler)
        }
        guard sonuc == noErr, uzunluk > 0 else { return nil }
        return String(utf16CodeUnits: harfler, count: uzunluk)
    }

    static func sonraki() {
        let l = liste
        guard !l.isEmpty else { return }
        let simdiki = kimlik(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        let i = l.firstIndex { kimlik($0) == simdiki } ?? -1
        TISSelectInputSource(l[(i + 1) % l.count])
    }
}

extension Sistem {
    /// Menü çubuğundaki saate basarak Bildirim Merkezi'ni açar (Erişilebilirlik).
    static func bildirimMerkezi() {
        guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return }
        let uyg = AXUIElementCreateApplication(cc.processIdentifier)
        var cubuk: CFTypeRef?
        guard AXUIElementCopyAttributeValue(uyg, "AXExtrasMenuBar" as CFString, &cubuk) == .success, let cubuk else { return }
        var cocuklar: CFTypeRef?
        AXUIElementCopyAttributeValue(cubuk as! AXUIElement, kAXChildrenAttribute as CFString, &cocuklar)
        for o in (cocuklar as? [AXUIElement]) ?? [] {
            var kimlik: CFTypeRef?
            AXUIElementCopyAttributeValue(o, kAXIdentifierAttribute as CFString, &kimlik)
            if (kimlik as? String) == "com.apple.menuextra.clock" { AXUIElementPerformAction(o, kAXPressAction as CFString); return }
        }
    }

    static func masaustunuGoster() { calistir("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"]) }
    static func ekranKoruyucu() { ac("/System/Library/CoreServices/ScreenSaverEngine.app") }
    static func uyut() { calistir("/usr/bin/pmset", ["sleepnow"]) }

    static func calistir(_ yol: String, _ arg: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = arg
        try? p.run()
    }

    /// Metni olduğu gibi yazar (emoji, öneri).
    static func yaz(_ metin: String) {
        let kaynak = CGEventSource(stateID: .hidSystemState)
        var parca = Array(metin.utf16)[...]
        while !parca.isEmpty {
            let p = Array(parca.prefix(16))
            parca = parca.dropFirst(16)
            for basili in [true, false] {
                guard let ev = CGEvent(keyboardEventSource: kaynak, virtualKey: 0, keyDown: basili) else { continue }
                ev.flags = []
                ev.keyboardSetUnicodeString(stringLength: p.count, unicodeString: p)
                ev.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Masaüstü alanları (Spaces): sayısı ve hangisinde olunduğu SkyLight'tan; geçiş ⌃1…⌃9 ile.
enum Alanlar {
    private static let kutup = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func durum() -> (sayi: Int, simdiki: Int) {
        typealias Baglanti = @convention(c) () -> Int32
        typealias Kopya = @convention(c) (Int32) -> Unmanaged<CFArray>?
        guard let b = dlsym(kutup, "CGSMainConnectionID"), let k = dlsym(kutup, "CGSCopyManagedDisplaySpaces"),
              let ekranlar = unsafeBitCast(k, to: Kopya.self)(unsafeBitCast(b, to: Baglanti.self)())?.takeRetainedValue() as? [[String: Any]],
              let ekran = ekranlar.first,
              let alanlar = ekran["Spaces"] as? [[String: Any]]
        else { return (1, 0) }
        let masaustleri = alanlar.filter { ($0["type"] as? Int) == 0 }
        let simdikiId = (ekran["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        let i = masaustleri.firstIndex { ($0["ManagedSpaceID"] as? Int) == simdikiId } ?? -1
        return (max(1, masaustleri.count), i)
    }

    static func git(_ i: Int) {
        let kodlar: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard i < kodlar.count else { return }
        Sistem.tus(kodlar[i], .maskControl, karakter: "\(i + 1)")
    }
}

/// True Tone benzeri renk sıcaklığı: çubuğun üstüne çarpılan sıcak bir ton (Touch Bar'ın ortam ışığı algılayıcısına erişilemiyor).
enum RenkSicakligi: String, CaseIterable {
    case kapali, ilik, sicak, nightShift

    var ad: String {
        switch self {
        case .kapali: L("Kapalı")
        case .ilik: L("Ilık")
        case .sicak: L("Sıcak")
        case .nightShift: L("Night Shift açıkken")
        }
    }

    /// Sıcak tonun gücü (0 = yok).
    func guc(nightShift: Bool) -> Double {
        switch self {
        case .kapali: 0
        case .ilik: 0.5
        case .sicak: 1
        case .nightShift: nightShift ? 1 : 0
        }
    }
}
