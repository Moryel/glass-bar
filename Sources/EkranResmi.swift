import AppKit

// ⇧⌘5 ekran resmi aracı: araç açıkken çubuk orijinaldeki gibi yakalama/kayıt tuşlarını ve "Şuraya kaydet"i gösterir.
// Tuşlar aracın kendi düğmelerine Erişilebilirlik ile basar; seçili kip ve kayıt yeri aracın ayarlarından okunur.
struct EkranAraci: Equatable {
    /// display, window, selection
    var stil = "display"
    var video = false
    var hedef = "Masaüstü"

    static let paket = "com.apple.screencaptureui"

    /// Aracın düğme kimlikleri (SF Symbols adları) ve sırası: önce üç yakalama, sonra üç kayıt.
    static let yakalama: [(kimlik: String, stil: String)] = [
        ("menubar.dock.rectangle", "display"), ("macwindow", "window"), ("rectangle.dashed", "selection")]
    static let kayit: [(kimlik: String, stil: String)] = [
        ("menubar.dock.rectangle.badge.record", "display"), ("macwindow.badge.record", "window"),
        ("rectangle.dashed.badge.record", "selection")]

    /// Düğmenin simgesi: "macwindow.badge.record" SF Symbols'te yok; orijinal Touch Bar'da imleçli pencere.
    static func simge(_ kimlik: String) -> String {
        kimlik == "macwindow.badge.record" ? "macwindow.and.cursorarrow" : kimlik
    }
    /// "Seçenekler" menüsündeki kayıt yerleri, menüdeki sırayla (anahtar Türkçe; ekranda L() ile sistemin dilinde)
    static let hedefler = ["Masaüstü", "Belgeler", "Pano", "Mail", "Önizleme", "Başka Bir Yer…"]

    /// Araç ekranda mı (işlem açık kalabiliyor; ekranda penceresi varsa açık sayılır). Ana iş parçacığında, ucuz.
    static func acik() -> Bool {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: paket).first else { return false }
        let pid = a.processIdentifier
        guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return l.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
    }

    /// Seçili kip ve kayıt yeri aracın ayarlarından.
    static func oku() -> EkranAraci {
        let alan = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(alan)
        func deger(_ k: String) -> Any? { CFPreferencesCopyAppValue(k as CFString, alan) }
        var d = EkranAraci()
        d.stil = deger("style") as? String ?? "display"
        d.video = (deger("video") as? Int ?? 0) != 0
        switch deger(d.video ? "target-screenrecording" : "target-screenshot") as? String ?? "file" {
        case "clipboard": d.hedef = "Pano"
        case "mail": d.hedef = "Mail"
        case "preview": d.hedef = "Önizleme"
        default:
            let yol = (deger("location") as? String).map { ($0 as NSString).expandingTildeInPath } ?? ""
            let ev = NSHomeDirectory()
            if yol.isEmpty || yol == ev + "/Desktop" { d.hedef = "Masaüstü" }
            else if yol == ev + "/Documents" { d.hedef = "Belgeler" }
            else { d.hedef = FileManager.default.displayName(atPath: yol) }
        }
        return d
    }

    // MARK: aracın düğmeleri (arka kuyrukta)
    private static var uygulama: AXUIElement? {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: paket).first else { return nil }
        let u = AXUIElementCreateApplication(a.processIdentifier)
        AXUIElementSetMessagingTimeout(u, 0.5)
        return u
    }

    private static func ozellik(_ o: AXUIElement, _ k: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, k as CFString, &v) == .success ? v : nil
    }

    /// Ağaçta koşula uyan ilk öğe (araç küçük: pencere → grup → düğmeler, menü öğeleri pencerenin altında).
    private static func bul(_ o: AXUIElement, _ d: Int = 0, _ kosul: (AXUIElement) -> Bool) -> AXUIElement? {
        if kosul(o) { return o }
        guard d < 4, let c = ozellik(o, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for x in c { if let b = bul(x, d + 1, kosul) { return b } }
        return nil
    }

    static func bas(_ kimlik: String) {
        guard let u = uygulama, let b = bul(u, 0, { ozellik($0, kAXIdentifierAttribute) as? String == kimlik }) else { return }
        AXUIElementPerformAction(b, kAXPressAction as CFString)
    }

    static func kapat() { bas("multiply.circle.fill") }

    /// Seçenekler menüsünü açıp kayıt yerini seçer. Öğe başlığıyla değil menüdeki sırasıyla bulunur
    /// (kimlikler: kayıt yerleri "optionsSaveTo:", sonuncusu "showOtherPicker:"), böylece her dilde çalışır.
    static func hedefSec(_ ad: String) {
        guard let u = uygulama, let sira = hedefler.firstIndex(of: ad),
              let m = bul(u, 0, { ozellik($0, kAXRoleAttribute) as? String == "AXMenuButton" }) else { return }
        AXUIElementPerformAction(m, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.3)
        var ogeler: [AXUIElement] = []
        func topla(_ o: AXUIElement, _ d: Int) {
            let id = ozellik(o, kAXIdentifierAttribute) as? String
            if id == "optionsSaveTo:" || id == "showOtherPicker:" { ogeler.append(o) }
            guard d < 3 else { return }
            for c in ozellik(o, kAXChildrenAttribute) as? [AXUIElement] ?? [] { topla(c, d + 1) }
        }
        topla(u, 0)
        if sira < ogeler.count {
            AXUIElementPerformAction(ogeler[sira], kAXPressAction as CFString)
        } else {
            AXUIElementPerformAction(m, kAXCancelAction as CFString)
        }
    }
}
