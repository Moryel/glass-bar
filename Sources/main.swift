import AppKit
import ServiceManagement
import SwiftUI

// Touch Bar'ı sistem kipinde kaplamak için özel API'ler (DFRFoundation ve NSTouchBar'ın gizli sınıf yöntemleri).
// MTMR ve Pock da aynı yolu kullanır.
enum DFR {
    private static let kutup = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    static func seritte(_ kimlik: String, _ goster: Bool) {
        typealias F = @convention(c) (CFString, Bool) -> Void
        guard let f = dlsym(kutup, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(f, to: F.self)(kimlik as CFString, goster)
    }

    static func kapatmaKutusu(_ goster: Bool) {
        typealias F = @convention(c) (Bool) -> Void
        guard let f = dlsym(kutup, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        unsafeBitCast(f, to: F.self)(goster)
    }

    private static func sinifYontemi(_ sinif: AnyClass, _ adlar: [String]) -> (Selector, IMP)? {
        for ad in adlar {
            let sel = NSSelectorFromString(ad)
            if let m = class_getClassMethod(sinif, sel) { return (sel, method_getImplementation(m)) }
        }
        return nil
    }

    /// placement 1: çubuğun tamamını (Control Strip dahil) kaplar.
    static func sun(_ tb: NSTouchBar, tepsi: String) {
        guard let (sel, imp) = sinifYontemi(NSTouchBar.self, ["presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
                                                              "presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"])
        else { return }
        typealias F = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
        unsafeBitCast(imp, to: F.self)(NSTouchBar.self, sel, tb, 1, tepsi as NSString)
    }

    static func kucult(_ tb: NSTouchBar) { tekli(NSTouchBar.self, ["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"], tb) }
    static func kaldir(_ tb: NSTouchBar) { tekli(NSTouchBar.self, ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"], tb) }
    static func tepsiyeEkle(_ o: NSTouchBarItem) { tekli(NSTouchBarItem.self, ["addSystemTrayItem:"], o) }
    static func tepsidenCikar(_ o: NSTouchBarItem) { tekli(NSTouchBarItem.self, ["removeSystemTrayItem:"], o) }

    private static func tekli(_ sinif: AnyClass, _ adlar: [String], _ arg: AnyObject) {
        guard let (sel, imp) = sinifYontemi(sinif, adlar) else { return }
        typealias F = @convention(c) (AnyClass, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: F.self)(sinif, sel, arg)
    }
}

final class Temsilci: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate {
    let durum = Durum()
    let cubuk = NSTouchBar()
    let anaKimlik = NSTouchBarItem.Identifier("com.yukselozge.glassbar.ana")
    let tepsiKimlik = NSTouchBarItem.Identifier("com.yukselozge.glassbar.tepsi")
    lazy var tepsi: NSCustomTouchBarItem = {
        let o = NSCustomTouchBarItem(identifier: tepsiKimlik)
        let b = NSButton(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GlassBar")!,
                         target: self, action: #selector(goster))
        o.view = b
        return o
    }()
    var durumOgesi: NSStatusItem!
    var kucuk = false
    var izleyiciler: [Any] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // tanı için: ~/Library/Logs/GlassBar.log
        let gunluk = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GlassBar.log")
        try? "\(Date()) açıldı · Erişilebilirlik: \(Sistem.erisimVar ? "var" : "YOK") · model: \(Donanim.model)\n"
            .write(to: gunluk, atomically: true, encoding: .utf8)
        if !Sistem.erisimVar { Sistem.erisimIste() }
        durum.yenile()
        durum.uygulamaDegisti(NSWorkspace.shared.frontmostApplication)
        durum.uygulamaTuslari = { [weak self] in self?.kucult() }
        durum.arkaResmiYenile()

        cubuk.delegate = self
        cubuk.defaultItemIdentifiers = [anaKimlik]
        DFR.tepsiyeEkle(tepsi)
        DFR.seritte(tepsiKimlik.rawValue, true)
        DFR.kapatmaKutusu(false)
        goster()

        menuKur()

        let ws = NSWorkspace.shared.notificationCenter
        izleyiciler.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            self.durum.uygulamaDegisti(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            self.listeyiUygula()
        })
        izleyiciler.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.durum.alanlar = Alanlar.durum()
            if self?.durum.arkaPlan == .duvarKagidi { self?.durum.arkaResmiYenile() }
        })
        // Spotiw elle açılıp X'iyle kapatılınca sistemin eski çubuğu yerine GlassBar geri gelir
        izleyiciler.append(DistributedNotificationCenter.default().addObserver(forName: .init(Spotiw.kimlik + ".didHide"), object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.kucuk else { return }
            self.goster()
        })

        // fn basılı tutulunca F1–F12
        let fn: (NSEvent) -> Void = { [weak self] e in
            let basili = e.modifierFlags.contains(.function)
            if self?.durum.fn != basili { self?.durum.fn = basili }
        }
        izleyiciler.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: fn) as Any)
        izleyiciler.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { fn($0); return $0 } as Any)

        // fiziksel esc de Siri hapını ve kaydırıcıyı kapatsın
        izleyiciler.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.durum.escBasildi() }
        } as Any)

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.durum.calanYenile()
            self?.durum.kisiYenile()
            self?.durum.takvimYenile()
            self?.durum.safariYenile()
        }
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.durum.onerileriYenile()
            self?.durum.ekranAraciYenile()
            self?.durum.fotoYenile()
        }
        listeyiUygula()

        // ekran görüntüsü denemeleri için: open GlassBar.app --args -tb2kip genis|parlaklik|ses|siri|fn
        switch UserDefaults.standard.string(forKey: "tb2kip") {
        case "genis": durum.kip = .genis
        case "parlaklik": durum.kip = .parlaklik
        case "ses": durum.kip = .ses
        case "siri": DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.durum.siri = true; Mikrofon.ortak.baslat() }
        case "siriDemo": DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.durum.siri = true }
        case "fn": durum.fn = true
        case "emoji": durum.kip = .emoji
        case "simdi": durum.kip = .simdi
        case "seritDuzenle": durum.seritDuzenle = true
        case "sekmeler": DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.durum.sekmeleriAc() }
        default: break
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        DFR.kaldir(cubuk)
        DFR.seritte(tepsiKimlik.rawValue, false)
        DFR.tepsidenCikar(tepsi)
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier kimlik: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard kimlik == anaKimlik else { return nil }
        let o = NSCustomTouchBarItem(identifier: kimlik)
        let gorunum = NSHostingView(rootView: Cubuk(d: durum))
        gorunum.translatesAutoresizingMaskIntoConstraints = false
        let w = gorunum.widthAnchor.constraint(equalToConstant: durum.genislik)
        w.priority = .defaultHigh
        NSLayoutConstraint.activate([w, gorunum.heightAnchor.constraint(equalToConstant: Olcu.yukseklik)])
        o.view = gorunum
        return o
    }

    @objc func goster() {
        kucuk = false
        durum.yenile()
        DFR.sun(cubuk, tepsi: tepsiKimlik.rawValue)
    }

    @objc func kucult() {
        kucuk = true
        DFR.kucult(cubuk)
    }

    /// "Kendi çubuğu" listesindeki uygulamada GlassBar çekilir; başka uygulamaya geçince geri gelir.
    func listeyiUygula() {
        if durum.kendiCubugu.contains(durum.paket) {
            if !kucuk { kucult() }
        } else if kucuk {
            goster()
        }
    }

    // MARK: menü çubuğu
    /// Uygulama simgesinin tek renkli hâli: çubuk, iki tuş ve dalga (şablon; menü çubuğunda beyaz/siyah olur).
    static func menuSimgesi() -> NSImage {
        let simge = NSImage(size: NSSize(width: 26, height: 16), flipped: false) { _ in
            let serit = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 24, height: 10), xRadius: 5, yRadius: 5)
            serit.lineWidth = 1.4
            serit.stroke()
            for x in [4.0, 8.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 5.5, width: 3, height: 5), xRadius: 1, yRadius: 1).fill()
            }
            let dalga = NSBezierPath()
            for i in 0...24 {
                let u = Double(i) / 24
                let nokta = NSPoint(x: 12.5 + u * 10, y: 8 + 2.6 * pow(sin(.pi * u), 2) * sin(u * .pi * 3.2))
                i == 0 ? dalga.move(to: nokta) : dalga.line(to: nokta)
            }
            dalga.lineWidth = 1.2
            dalga.lineCapStyle = .round
            dalga.stroke()
            return true
        }
        simge.isTemplate = true
        simge.accessibilityDescription = "GlassBar"
        return simge
    }

    func menuKur() {
        durumOgesi = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        durumOgesi.button?.image = Temsilci.menuSimgesi()
        let m = NSMenu()
        m.delegate = self
        durumOgesi.menu = m
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        m.addItem(withTitle: L("GlassBar'ı göster"), action: #selector(goster), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Uygulamanın kendi tuşları"), action: #selector(kucult), keyEquivalent: "").target = self
        m.addItem(.separator())
        if !Sistem.erisimVar {
            m.addItem(withTitle: L("Erişilebilirlik izni ver…"), action: #selector(izinIste), keyEquivalent: "").target = self
        }
        if let ad = durum.uygulama?.localizedName {
            m.addItem(oge(String(format: L("“%@” için kendi Touch Bar'ını göster"), ad), #selector(kendiDegistir), durum.kendiCubugu.contains(durum.paket)))
            m.addItem(oge(String(format: L("“%@” için hep F1, F2 tuşlarını göster"), ad), #selector(hepFDegistir), durum.hepF.contains(durum.paket)))
            m.addItem(.separator())
        }
        m.addItem(altMenu(L("Touch Bar gösterir"), Gosterim.allCases.map { g in
            oge(g.ad, #selector(gosterimSec(_:)), durum.gosterim == g, g.rawValue)
        }))
        m.addItem(altMenu(L("fn tuşu basılı tutulunca"), Gosterim.allCases.map { g in
            oge(g.ad, #selector(fnSec(_:)), durum.fnBasili == g, g.rawValue)
        }))
        m.addItem(altMenu(L("Tema"), Tema.allCases.map { t in
            oge(t.ad, #selector(temaSec(_:)), durum.tema == t, t.rawValue)
        }))
        m.addItem(altMenu(L("Renk sıcaklığı"), RenkSicakligi.allCases.map { r in
            oge(r.ad, #selector(renkSicakligiSec(_:)), durum.renkSicakligi == r, r.rawValue)
        }))
        m.addItem(altMenu(L("Arka plan"), ArkaPlan.allCases.map { a in
            oge(a.ad, #selector(arkaPlanSec(_:)), durum.arkaPlan == a, a.rawValue)
        }))
        m.addItem(oge(L("Control Strip'i göster"), #selector(seritDegistir), durum.seritGoster))
        m.addItem(withTitle: L("Control Strip'i Özelleştir…"), action: #selector(seritiDuzenle), keyEquivalent: "").target = self
        m.addItem(altMenu(String(format: L("Control Strip tuşları (en çok %d)"), SeritTusu.enFazla), SeritTusu.allCases.map { t in
            oge(t.ad, #selector(seritTusuDegistir(_:)), durum.seritTuslari.contains(t), t.rawValue)
        }))
        m.addItem(oge(L("Yazma önerilerini göster"), #selector(oneriDegistir), durum.oneriAcik))
        m.addItem(oge(L("Çubukta esc tuşu"), #selector(escDegistir), durum.escGoster))
        let giris = m.addItem(withTitle: L("Mac açılınca başlat"), action: #selector(girisDegistir), keyEquivalent: "")
        giris.target = self
        giris.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: L("Çık"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func oge(_ ad: String, _ eylem: Selector, _ secili: Bool, _ deger: String? = nil) -> NSMenuItem {
        let o = NSMenuItem(title: ad, action: eylem, keyEquivalent: "")
        o.target = self
        o.state = secili ? .on : .off
        o.representedObject = deger
        return o
    }

    private func altMenu(_ ad: String, _ ogeler: [NSMenuItem]) -> NSMenuItem {
        let o = NSMenuItem(title: ad, action: nil, keyEquivalent: "")
        let alt = NSMenu()
        ogeler.forEach(alt.addItem)
        o.submenu = alt
        return o
    }

    @objc func escDegistir() { durum.escGoster.toggle() }
    @objc func seritDegistir() { durum.seritGoster.toggle() }
    @objc func renkSicakligiSec(_ o: NSMenuItem) {
        if let r = RenkSicakligi(rawValue: o.representedObject as? String ?? "") { durum.renkSicakligi = r }
    }

    @objc func arkaPlanSec(_ o: NSMenuItem) {
        guard let a = ArkaPlan(rawValue: o.representedObject as? String ?? "") else { return }
        if a == .gorsel { gorselSec() } else { durum.arkaPlan = a }
    }

    /// Arka plan için görsel seçtirir (uygulama arka planda çalıştığı için önce öne alınır).
    func gorselSec() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = L("Touch Bar'ın arkasında görünecek görseli seç")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        durum.arkaGorselYolu = url.path
        durum.arkaPlan = .gorsel
    }
    @objc func oneriDegistir() { durum.oneriAcik.toggle() }

    @objc func gosterimSec(_ o: NSMenuItem) {
        if let g = Gosterim(rawValue: o.representedObject as? String ?? "") { durum.gosterim = g; durum.kip = .uygulama }
    }

    @objc func temaSec(_ o: NSMenuItem) {
        if let t = Tema(rawValue: o.representedObject as? String ?? "") { durum.tema = t }
    }
    @objc func fnSec(_ o: NSMenuItem) {
        if let g = Gosterim(rawValue: o.representedObject as? String ?? "") { durum.fnBasili = g }
    }

    @objc func seritiDuzenle() {
        durum.kip = .uygulama
        durum.seritDuzenle = true
    }

    /// Seçilen tuş sona eklenir; sınır aşılırsa en eskisi çıkar.
    @objc func seritTusuDegistir(_ o: NSMenuItem) {
        guard let t = SeritTusu(rawValue: o.representedObject as? String ?? "") else { return }
        var l = durum.seritTuslari
        if let i = l.firstIndex(of: t) { l.remove(at: i) } else { l.append(t); if l.count > SeritTusu.enFazla { l.removeFirst() } }
        durum.seritTuslari = l
    }

    @objc func kendiDegistir() {
        let p = durum.paket
        if let i = durum.kendiCubugu.firstIndex(of: p) { durum.kendiCubugu.remove(at: i) } else { durum.kendiCubugu.append(p) }
        listeyiUygula()
    }

    @objc func hepFDegistir() {
        let p = durum.paket
        if let i = durum.hepF.firstIndex(of: p) { durum.hepF.remove(at: i) } else { durum.hepF.append(p) }
    }

    @objc func izinIste() {
        Sistem.erisimIste()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func girisDegistir() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }
}

/// Spotiw (github.com/Moryel/spotiw): Spotify oynatıcısını Touch Bar'da gösteren ayrı uygulama.
/// Çubuğu kapanınca dağıtık "didHide" bildirimi gönderir; GlassBar o zaman geri gelir.
enum Spotiw {
    static let kimlik = "com.yuksel.spotiw"
}

// Uygulamanın eski adı TouchBar2'ydi: ilk açılışta ayarları eski kimlikten taşı.
let eskiAyarlar = "com.yukselozge.TouchBar2"
if !UserDefaults.standard.bool(forKey: "ayarlarTasindi") {
    for (anahtar, deger) in UserDefaults.standard.persistentDomain(forName: eskiAyarlar) ?? [:]
    where UserDefaults.standard.object(forKey: anahtar) == nil {
        UserDefaults.standard.set(deger, forKey: anahtar)
    }
    UserDefaults.standard.set(true, forKey: "ayarlarTasindi")
}

let uygulama = NSApplication.shared
let temsilci = Temsilci()
uygulama.delegate = temsilci
uygulama.setActivationPolicy(.accessory)
uygulama.run()
