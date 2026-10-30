import AppKit
import SwiftUI

// Çubuğun durumu ve tuşların yaptığı işler.
final class Durum: ObservableObject {
    /// Geçici paneller; `.uygulama` iken çubuk ayardaki gösterimi izler.
    enum Kip { case uygulama, genis, parlaklik, ses, simdi, emoji, sekmeler }

    @Published var kip = Kip.uygulama
    @Published var fn = false
    @Published var siri = false
    @Published var parlaklik: Float = 0.5
    @Published var ses: Float = 0.5
    @Published var sessiz = false
    @Published var nightShift = false
    @Published var klavyeAdi = ""
    @Published var uygulama: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    @Published var renk = Color.blue
    @Published var calan: Calan?
    @Published var calanKonum: Float = 0
    @Published var oneriler = Oneriler()
    @Published var emojiKategori = 1
    @Published var alanlar = (sayi: 1, simdiki: 0)
    @Published var sekmeler: [Sekme] = []
    /// sekme şeridinde gösterilen Safari penceresi (1 = öndeki)
    @Published var sekmePencere = 1
    @Published var sekmeOkunuyor = false
    @Published var sekmeIzniYok = false
    /// açık açılır çubuk (popover)
    @Published var acilir: Acilir?
    /// basılı tutup kaydırırken parmağın altındaki öğe
    @Published var acilirParmak: Int?
    @Published var acilirKayiyor = false
    /// açılır çubuktaki öğe grubunun çubuktaki yeri (parmağın hangi öğede olduğunu bulmak için)
    var acilirAlan: CGRect = .zero
    /// Takvim'de gösterilen ay (ayın ilk günü)
    /// Takvim'in görünümü: gün, hafta ya da ay (yıl görünümünde de ay şeridi).
    @Published var takvimBirim = Calendar.Component.month
    @Published var takvimAy = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    /// Kişiler'de seçili kişi
    @Published var kisi: Kisi?
    /// Fotoğraflar'da açık video
    @Published var fotoVideo: FotoVideo?
    /// Safari'de oynatılan video
    @Published var safariVideo: SafariVideo?
    private var safariKareler = ""
    private var fotoKimlik = ""
    /// ⇧⌘5 aracı açıkken dolu; çubuk onun tuşlarını gösterir
    @Published var ekranAraci: EkranAraci?
    /// "Şuraya kaydet" listesi açık
    @Published var hedefListesi = false
    /// basılı tutup kaydırılırken görünen kaydırıcı
    @Published var canli: Kip?
    /// parlaklık/ses tuşlarının çubuktaki yeri (açılır kaydırıcı onun solunda açılır)
    var tusYeri: [Kip: CGRect] = [:]

    // MARK: ayarlar
    @Published var tema = Tema(rawValue: Kayit.yazi("tema")) ?? .klasik { didSet { Kayit.yaz("tema", tema.rawValue) } }
    /// Camın arkası; eski "Ortam ışığı" ayarı kapalıysa kapalı başlar
    @Published var renkSicakligi = RenkSicakligi(rawValue: Kayit.yazi("renkSicakligi")) ?? .kapali {
        didSet { Kayit.yaz("renkSicakligi", renkSicakligi.rawValue) }
    }
    @Published var arkaPlan = ArkaPlan(rawValue: Kayit.yazi("arkaPlan")) ?? (Kayit.evet("ortamIsigi", true) ? .uygulama : .kapali) {
        didSet { Kayit.yaz("arkaPlan", arkaPlan.rawValue); arkaResmiYenile() }
    }
    /// "Görsel seç…" ile seçilen dosya
    @Published var arkaGorselYolu = Kayit.yazi("arkaGorsel") { didSet { Kayit.yaz("arkaGorsel", arkaGorselYolu); arkaResmiYenile() } }
    /// duvar kağıdı ya da görselin çubuk ölçüsündeki şeridi
    @Published var arkaResim: NSImage?
    @Published var escGoster = Kayit.evet("escGoster", !Donanim.fizikselEsc) { didSet { Kayit.yaz("escGoster", escGoster) } }
    @Published var gosterim = Gosterim(rawValue: Kayit.yazi("gosterim")) ?? .uygulama { didSet { Kayit.yaz("gosterim", gosterim.rawValue) } }
    @Published var fnBasili = Gosterim(rawValue: Kayit.yazi("fnBasili")) ?? .fTuslari { didSet { Kayit.yaz("fnBasili", fnBasili.rawValue) } }
    @Published var seritGoster = Kayit.evet("seritGoster", true) { didSet { Kayit.yaz("seritGoster", seritGoster) } }
    @Published var oneriAcik = Kayit.evet("oneriAcik", true) { didSet { Kayit.yaz("oneriAcik", oneriAcik); if !oneriAcik { oneriler = Oneriler() } } }
    /// Control Strip düzenleme kipi (menüde "Control Strip'i Özelleştir…").
    @Published var seritDuzenle = false
    @Published var seritTuslari = (Kayit.dizi("seritTuslari") ?? []).compactMap(SeritTusu.init(rawValue:)).nilIfEmpty ?? SeritTusu.varsayilan {
        didSet { Kayit.yaz("seritTuslari", seritTuslari.map(\.rawValue)) }
    }
    /// bu uygulamalarda kendi Touch Bar'ı görünür
    @Published var kendiCubugu = Kayit.dizi("kendiCubugu") ?? [] { didSet { Kayit.yaz("kendiCubugu", kendiCubugu) } }
    /// bu uygulamalarda hep F1–F12
    @Published var hepF = Kayit.dizi("hepF") ?? [] { didSet { Kayit.yaz("hepF", hepF) } }

    let genislik = Donanim.genislik
    /// Öndeki uygulamanın kendi Touch Bar tuşlarını göstermek için (GlassBar küçülür).
    var uygulamaTuslari: () -> Void = {}
    /// Spotify'da Spotiw'in oynatıcısını kullan (Spotiw çalışıyorsa).
    @Published var spotiwKullan = Kayit.evet("spotiwKullan", true) { didSet { Kayit.yaz("spotiwKullan", spotiwKullan) } }
    var spotiwAc: () -> Void = {}

    private var kapatma: Timer?
    private var siriSuresi: Timer?
    private var sonSarma = Date.distantPast
    private var canliBaslangic: Float = 0

    var paket: String { uygulama?.bundleIdentifier ?? "" }

    /// fn basılıyken fn ayarı, "hep F tuşları" listesindeki uygulamada F tuşları, yoksa gösterim ayarı.
    var etkin: Gosterim {
        if fn { return fnBasili }
        if hepF.contains(paket) { return .fTuslari }
        return gosterim
    }

    var anahtar: String { "\(etkin)\(kip)\(siri)\(paket)\(escGoster)\(seritGoster)\(canli.map { "\($0)" } ?? "")\(calan != nil)\(oneriler.aktif)\(oneriKapali)\(emojiKategori)\(acilir != nil)\(seritDuzenle)" }

    // MARK: esc, fn
    func esc() {
        escBasildi()
        Sistem.tus(53)
    }

    /// esc (çubuktaki ya da fiziksel) açık Siri hapını ve geçici panelleri kapatır.
    func escBasildi() {
        if acilir != nil { acilirKapat(); return }
        if seritDuzenle { seritDuzenle = false; return }
        if ekranAraci != nil { Sistem.arka.async { EkranAraci.kapat() } }
        if siri { siriKapat() }
        if kip != .uygulama && kip != .genis { kip = .uygulama }
    }

    func fnTusu(_ i: Int) {
        let kodlar: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        // klavyede basılı tutulan ⌃⌥⇧⌘ de eklenir (fn+⌃+F3 gibi)
        let basili = CGEventSource.flagsState(.hidSystemState).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        Sistem.tus(kodlar[i - 1], basili.union(.maskSecondaryFn))
    }

    // MARK: Control Strip
    func genislet() { yenile(); kip = .genis }
    func daralt() { kip = .uygulama }

    func kaydirici(_ k: Kip) {
        yenile()
        kip = k
        sonraKapat()
    }

    /// Kaydırıcı açık kalırsa bir süre dokunulmayınca kapanır (orijinaldeki gibi).
    private func sonraKapat() {
        kapatma?.invalidate()
        kapatma = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, self.kip == .parlaklik || self.kip == .ses else { return }
            self.kip = .uygulama
        }
    }

    func parlaklikAyarla(_ v: Float) { Ekran.parlaklik = v; sonraKapat() }

    func sesAyarla(_ v: Float) {
        Ses.seviye = v
        sessiz = false
        sonraKapat()
    }

    /// Parlaklık/ses tuşuna basıp parmağı kaldırmadan kaydırma: tuşun üstünde kaydırıcı belirir, değer anında değişir.
    func canliKaydir(_ k: Kip, _ dx: CGFloat) {
        if canli == nil {
            yenile()
            canliBaslangic = k == .parlaklik ? parlaklik : ses
            canli = k
        }
        let v = min(1, max(0, canliBaslangic + Float(dx / 320)))
        if k == .parlaklik { parlaklik = v; Ekran.parlaklik = v } else { ses = v; Ses.seviye = v; sessiz = false }
    }

    func canliBitti() { canli = nil }

    /// Açılır kaydırıcının uçlarındaki simgeler: 1/16'lık adım (sistemin kendi adımı kadar).
    func kaydiriciAdim(_ k: Kip, _ yon: Float) {
        if k == .parlaklik {
            parlaklik = min(1, max(0, parlaklik + yon / 16))
            Ekran.parlaklik = parlaklik
        } else {
            ses = min(1, max(0, ses + yon / 16))
            Ses.seviye = ses
            sessiz = false
        }
        sonraKapat()
    }

    func sessizDegistir() {
        if Sistem.erisimVar { Sistem.ozelTus(.sessiz) } else { Ses.sessiz.toggle() }
        sonraYenile()
    }

    /// Adım tuşları sistemin kendi göstergesini çıkarsın diye medya tuşu gönderir; izin yoksa doğrudan ayarlar.
    func adim(_ t: Sistem.Ozel) {
        if Sistem.erisimVar {
            Sistem.ozelTus(t)
        } else {
            let d: Float = 1 / 16
            switch t {
            case .parlaklikArti: Ekran.parlaklik += d
            case .parlaklikEksi: Ekran.parlaklik -= d
            case .sesArti: Ses.seviye += d
            case .sesEksi: Ses.seviye -= d
            case .klavyeArti: KlavyeIsigi.deger += d
            case .klavyeEksi: KlavyeIsigi.deger -= d
            case .sessiz: Ses.sessiz.toggle()
            case .oynat: calan?.oynatDuraklat()
            case .sonraki: calan?.sonraki()
            case .onceki: calan?.onceki()
            }
        }
        sonraYenile()
    }

    func seritEylem(_ t: SeritTusu) {
        switch t {
        case .parlaklik: kaydirici(.parlaklik)
        case .ses: kaydirici(.ses)
        case .sessiz: sessizDegistir()
        case .oynat: if let calan { calan.oynatDuraklat(); sonraYenile() } else { adim(.oynat) }
        case .siri: siriDegistir()
        case .missionControl: Sistem.missionControl()
        case .launchpad: Sistem.launchpad()
        case .spotlight: Sistem.tus(49, .maskCommand, karakter: " ")
        case .bildirim: Sistem.bildirimMerkezi()
        case .nightShift: NightShift.acik.toggle(); nightShift = NightShift.acik
        case .ekranResmi: Sistem.tus(23, [.maskCommand, .maskShift], karakter: "5")
        case .girisKaynagi: GirisKaynagi.sonraki(); klavyeAdi = GirisKaynagi.kisaAd
        case .masaustu: Sistem.masaustunuGoster()
        case .ekranKoruyucu: Sistem.ekranKoruyucu()
        case .kilitle: Sistem.tus(12, [.maskCommand, .maskControl], karakter: "q")
        case .uyut: Sistem.uyut()
        case .klavye:
            acilirAc(Acilir(ogeler: [AcilirOge(simge: "light.min") { self.adim(.klavyeEksi) },
                                     AcilirOge(simge: "light.max") { self.adim(.klavyeArti) }]))
        case .dikte: menu("startDictation:")
        case .hizliEylem: altMenuAc(nil, ["Servisler", "Services"], baslik: "Hızlı Eylemler")
        }
    }

    func yenile() {
        parlaklik = Ekran.parlaklik
        ses = Ses.seviye
        sessiz = Ses.sessiz
        nightShift = NightShift.acik
        klavyeAdi = GirisKaynagi.kisaAd
        alanlar = Alanlar.durum()
    }

    private func sonraYenile() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.yenile()
            self?.calanYenile()
        }
    }

    // MARK: Siri
    func siriDegistir() { siri ? siriKapat() : siriAc() }

    func siriAc() {
        Sistem.siri()
        kip = .uygulama
        siri = true
        Mikrofon.ortak.baslat()
        siriSuresi?.invalidate()
        siriSuresi = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.siriKapat() }
    }

    func siriKapat() {
        siriSuresi?.invalidate()
        if siri { Mikrofon.ortak.durdur() }
        siri = false
    }

    // MARK: öndeki uygulama
    func uygulamaDegisti(_ a: NSRunningApplication?) {
        guard let a, a.activationPolicy == .regular, a.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        // aynı uygulama yeniden öne gelince (izin penceresi kapanınca gibi) açık paneller kapanmasın
        let ayni = a.bundleIdentifier == uygulama?.bundleIdentifier
        uygulama = a
        if ayni { return }
        acilirKapat()
        kisi = nil
        renk = Color(nsColor: a.icon?.baskinRenk ?? .systemBlue)
        if a.bundleIdentifier != "com.apple.Siri" { siriKapat() }
        if kip == .emoji || kip == .sekmeler { kip = .uygulama }
        oneriler = Oneriler()
        calanYenile()
    }

    // MARK: Şimdi Oynatılan
    private var calanOkunuyor = false
    private var oneriOkunuyor = false

    func calanYenile() {
        guard !calanOkunuyor else { return }
        calanOkunuyor = true
        let onde = paket
        let calisan = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Sistem.arka.async {
            let c = Calan.oku(onde: onde, calisan: calisan)
            DispatchQueue.main.async {
                self.calanOkunuyor = false
                self.calanUygula(c)
            }
        }
    }

    private func calanUygula(_ c: Calan?) {
        if c != calan { calan = c }
        FilmSeridi.ortak.yukle(c?.video == true ? c?.dosya : nil)
        if let c, Date().timeIntervalSince(sonSarma) > 1.5 { calanKonum = Float(c.konum / c.sure) }
        if c == nil && kip == .simdi { kip = .uygulama }
    }

    /// Sürüklerken saniyede en çok ~7 kez sarar; parmak kalkınca `zorla` ile son konuma.
    func calanSar(_ v: Float, zorla: Bool = false) {
        guard let c = calan, zorla || Date().timeIntervalSince(sonSarma) > 0.15 else { return }
        sonSarma = Date()
        c.git(Double(v) * c.sure)
    }

    func calanKomut(_ k: (Calan) -> Void) {
        guard let c = calan else { return }
        k(c)
        sonraYenile()
    }

    // MARK: ekran resmi aracı
    /// main.swift'teki zamanlayıcıdan; araç açılınca/kapanınca çubuk değişir.
    func ekranAraciYenile() {
        let acik = EkranAraci.acik()
        if !acik {
            if ekranAraci != nil { ekranAraci = nil; hedefListesi = false }
            return
        }
        let d = EkranAraci.oku()
        if d != ekranAraci { ekranAraci = d }
    }

    func ekranKipi(_ kimlik: String, stil: String, video: Bool) {
        ekranAraci?.stil = stil
        ekranAraci?.video = video
        Sistem.arka.async { EkranAraci.bas(kimlik) }
    }

    func ekranHedefi(_ ad: String) {
        hedefListesi = false
        if ad != "Başka Bir Yer…" { ekranAraci?.hedef = ad }
        Sistem.arka.async { EkranAraci.hedefSec(ad) }
    }

    // MARK: açılır çubuk
    func acilirAc(_ a: Acilir) {
        acilirParmak = nil
        acilir = a
    }

    func acilirKapat() {
        acilir = nil
        acilirParmak = nil
        acilirKayiyor = false
    }

    /// Basılı tutup kaydırma: çubuk açık değilse açılır, parmağın altındaki öğe vurgulanır.
    func acilirKaydir(_ x: CGFloat, _ uret: () -> Acilir) {
        if !acilirKayiyor { acilirKayiyor = true }
        if acilir == nil { acilirAc(uret()) }
        guard let n = acilir?.ogeler.count, n > 0, n <= 8, acilirAlan.width > 0 else { return }
        let i = Int(floor((x - acilirAlan.minX) / (acilirAlan.width / CGFloat(n))))
        let yeni = (0..<n).contains(i) ? i : nil
        if yeni != acilirParmak { acilirParmak = yeni }
    }

    /// Parmak kalkınca altındaki öğe seçilir; öğenin dışında kalkarsa çubuk açık kalır.
    func acilirBirak() {
        acilirKayiyor = false
        guard let a = acilir, let i = acilirParmak, i < a.ogeler.count else { acilirParmak = nil; return }
        acilirKapat()
        a.ogeler[i].eylem()
    }

    // MARK: menü komutları
    /// Öndeki uygulamanın menü öğesine basar: kimliğiyle ya da başlıklarından biriyle.
    func menu(_ kimlik: String? = nil, _ basliklar: String...) {
        guard let pid = uygulama?.processIdentifier else { return }
        Sistem.arka.async {
            let tamam = AX.menuKomut(pid, kimlik: kimlik, basliklar: basliklar)
            Sistem.gunluk("menü \(kimlik ?? basliklar.first ?? ""): \(tamam ? "tamam" : "bulunamadı")")
        }
    }

    /// Bir alt menünün öğelerini (Mail'de posta kutuları, bayrak renkleri, Servisler) açılır çubukta gösterir.
    func altMenuAc(_ kimlik: String?, _ basliklar: [String], baslik: String) {
        guard let pid = uygulama?.processIdentifier else { return }
        acilirAc(Acilir(baslik: baslik, ogeler: [], bilgi: "Okunuyor…"))
        Sistem.arka.async {
            let l = AX.altMenu(pid, kimlik: kimlik, basliklar: basliklar)
            DispatchQueue.main.async {
                guard self.acilir?.baslik == baslik else { return }
                self.acilir = Acilir(baslik: baslik, ogeler: l.map { t in
                    AcilirOge(yazi: t) { Sistem.arka.async { AX.altMenuSec(pid, kimlik: kimlik, basliklar: basliklar, t) } }
                }, bilgi: "Şu an seçilebilecek bir şey yok")
            }
        }
    }

    /// Öndeki penceredeki düğmeye basar (Hesap Makinesi).
    func pencereDugmesi(_ kimlik: String) {
        guard let pid = uygulama?.processIdentifier else { return }
        Sistem.arka.async { AX.pencereDugmesi(pid, kimlik) }
    }

    // MARK: Takvim
    func takvimGit(_ ay: Date) {
        takvimAy = ay
        let c = Calendar.current.dateComponents([.year, .month, .day], from: ay)
        Sistem.betikArka("""
        set g to current date
        set day of g to 1
        set year of g to \(c.year ?? 2026)
        set month of g to \(c.month ?? 1)
        set day of g to \(takvimBirim == .month ? 1 : c.day ?? 1)
        tell application "Calendar" to view calendar at g
        """)
    }

    func takvimBugun() {
        takvimAy = Durum.birimBasi(Date(), takvimBirim)
        Sistem.betikArka("tell application \"Calendar\" to view calendar at (current date)")
    }

    static func birimBasi(_ t: Date, _ b: Calendar.Component) -> Date {
        let c = Calendar.current
        switch b {
        case .day: return c.startOfDay(for: t)
        case .weekOfYear: return c.dateInterval(of: .weekOfYear, for: t)?.start ?? t
        default: return c.date(from: c.dateComponents([.year, .month], from: t)) ?? t
        }
    }

    /// main.swift'teki zamanlayıcıdan; Takvim öndeyken Görüntü menüsünde işaretli birimi okur.
    func takvimYenile() {
        guard paket == "com.apple.iCal", kip == .uygulama, let pid = uygulama?.processIdentifier else { return }
        Sistem.arka.async {
            let b: Calendar.Component = AX.isaretli(pid, "Gün") ? .day : AX.isaretli(pid, "Hafta") ? .weekOfYear : .month
            DispatchQueue.main.async {
                guard b != self.takvimBirim else { return }
                self.takvimBirim = b
                self.takvimAy = Durum.birimBasi(self.takvimAy, b)
            }
        }
    }

    // MARK: Kişiler
    /// main.swift'teki zamanlayıcıdan; yalnız Kişiler öndeyken seçili kişiyi okur.
    func kisiYenile() {
        guard paket == Kisi.paket, kip == .uygulama else { return }
        Sistem.arka.async {
            let k = Kisi.oku()
            DispatchQueue.main.async { if k != self.kisi { self.kisi = k } }
        }
    }

    // MARK: Fotoğraflar videosu
    /// main.swift'teki zamanlayıcıdan; yalnız Fotoğraflar öndeyken oynatıcıyı okur.
    func fotoYenile() {
        guard paket == FotoOynatici.paket, kip == .uygulama, let pid = uygulama?.processIdentifier else {
            if fotoVideo != nil { fotoVideo = nil }
            return
        }
        Sistem.arka.async {
            let v = FotoOynatici.oku(pid)
            DispatchQueue.main.async {
                // sürüklerken okunan eski konum oynatma başını geri çekmesin
                if var v, Date().timeIntervalSince(self.sonSarma) < 1.5, let eski = self.fotoVideo { v.konum = eski.konum; self.fotoVideo = v }
                else if v != self.fotoVideo { self.fotoVideo = v }
                guard let v, v.kimlik != self.fotoKimlik else { return }
                self.fotoKimlik = v.kimlik
                FilmSeridi.foto.yukle(nil)
                Sistem.arka.async {
                    let yol = FotoOynatici.disaAktar()
                    Sistem.gunluk("foto video: \(yol == nil ? "aktarılamadı" : "aktarıldı")")
                    DispatchQueue.main.async { if self.fotoKimlik == v.kimlik { FilmSeridi.foto.yukle(yol) } }
                }
            }
        }
    }

    /// Sürüklerken saniyede en çok ~7 kez sarar; parmak kalkınca `zorla` ile son konuma.
    func fotoSar(_ v: Float, zorla: Bool = false) {
        guard let pid = uygulama?.processIdentifier, zorla || Date().timeIntervalSince(sonSarma) > 0.15 else { return }
        sonSarma = Date()
        Sistem.arka.async { FotoOynatici.sar(pid, v) }
    }

    // MARK: arka plan
    /// Duvar kağıdı/görsel seçiliyse şeridi hazırlar (açılışta, seçim değişince, masaüstü değişince).
    func arkaResmiYenile() {
        let url: URL? = switch arkaPlan {
        case .duvarKagidi: ArkaPlan.duvarKagidiAdresi
        case .gorsel: arkaGorselYolu.isEmpty ? nil : URL(fileURLWithPath: arkaGorselYolu)
        default: nil
        }
        guard let url else { arkaResim = nil; return }
        let w = genislik
        Sistem.arka.async {
            let r = ArkaPlan.serit(url, genislik: w)
            if r == nil { Sistem.gunluk("arka plan: görsel okunamadı (\(url.lastPathComponent))") }
            DispatchQueue.main.async { self.arkaResim = r }
        }
    }

    // MARK: Safari videosu
    /// main.swift'teki zamanlayıcıdan; yalnız Safari öndeyken sayfadaki videoyu okur. Oynatılmaya başlamış
    /// (ya da oynayan) video varsa Safari çubuğu oynatıcıya döner.
    func safariYenile() {
        guard paket == "com.apple.Safari", kip == .uygulama, !siri else {
            if safariVideo != nil { safariVideo = nil }
            return
        }
        Sistem.arka.async {
            var v = SafariOynatici.oku()
            if let x = v, x.duraklatildi && x.gecen < 0.5 { v = nil }
            DispatchQueue.main.async {
                if var v, Date().timeIntervalSince(self.sonSarma) < 1.5, let eski = self.safariVideo { v.konum = eski.konum; self.safariVideo = v }
                else if v != self.safariVideo { self.safariVideo = v }
                guard let v else { return }
                let anahtar = v.adres + v.kareler
                guard anahtar != self.safariKareler else { return }
                self.safariKareler = anahtar
                FilmSeridi.safari.ayarla([], anahtar: anahtar)
                guard !v.kareler.isEmpty else { return }
                Sistem.arka.async {
                    let r = SafariOynatici.kucukResimler(v.kareler, adet: FilmSeridi.adet)
                    Sistem.gunluk("safari video: \(r.count) küçük resim")
                    DispatchQueue.main.async { if self.safariKareler == anahtar { FilmSeridi.safari.ayarla(r, anahtar: anahtar) } }
                }
            }
        }
    }

    func safariSar(_ v: Float, zorla: Bool = false) {
        guard let s = safariVideo, zorla || Date().timeIntervalSince(sonSarma) > 0.15 else { return }
        sonSarma = Date()
        let saniye = Double(v) * s.sure
        Sistem.arka.async { SafariOynatici.sar(saniye) }
    }

    func safariAtla(_ fark: Double) {
        guard let s = safariVideo else { return }
        let saniye = min(s.sure, max(0, s.gecen + fark))
        safariVideo?.konum = Float(saniye / s.sure)
        sonSarma = Date()
        Sistem.arka.async { SafariOynatici.sar(saniye) }
    }

    func safariOynat() {
        safariVideo?.duraklatildi.toggle()
        sonSarma = Date()
        Sistem.arka.async { SafariOynatici.oynatDuraklat() }
    }

    // MARK: Mesajlar
    /// Tapback: 1 kalp, 2 beğen, 3 beğenme, 4 kahkaha, 5 ünlem, 6 soru.
    func tapback(_ n: Int) {
        guard let pid = uygulama?.processIdentifier else { return }
        Sistem.arka.async {
            guard AX.menuKomut(pid, kimlik: "keyCommandTapback:") else { return }
            Thread.sleep(forTimeInterval: 0.35)
            Sistem.yaz("\(n)")
        }
    }

    // MARK: Safari sekmeleri
    func sekmeleriAc() {
        sekmePencere = 1
        kip = .sekmeler
        sekmeleriYenile()
    }

    func sekmeleriYenile() {
        sekmeOkunuyor = true
        Sistem.arka.async {
            let okunan = Sekme.oku()
            let l = okunan ?? []
            Sistem.gunluk(okunan == nil ? "sekmeler: Safari'ye erişilemedi" : "sekmeler: \(l.count) sekme")
            DispatchQueue.main.async {
                self.sekmeOkunuyor = false
                self.sekmeIzniYok = okunan == nil
                if l != self.sekmeler { self.sekmeler = l }
                if !l.contains(where: { $0.pencere == self.sekmePencere }) { self.sekmePencere = l.first?.pencere ?? 1 }
            }
        }
    }

    func sekmeleriSonraYenile() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.sekmeleriYenile() }
    }

    func sekmeSec(_ s: Sekme) {
        // seçilen pencere öne gelince numarası 1 olur
        Sistem.arka.async {
            s.sec()
            DispatchQueue.main.async { self.sekmePencere = 1; self.sekmeleriYenile() }
        }
    }

    // MARK: yazma önerileri
    /// Yalnız yazı yazılan yerlerde: Finder, Müzik, QuickTime dışında ve uygulama tuşları görünürken.
    func onerileriYenile() {
        guard oneriAcik, Sistem.erisimVar, kip == .uygulama, etkin == .uygulama, !siri,
              !["com.apple.finder", Calan.muzik, Calan.quickTime, Calan.spotify].contains(paket)
        else { if oneriler.aktif { oneriler = Oneriler() }; return }
        guard !oneriOkunuyor else { return }
        oneriOkunuyor = true
        Sistem.arka.async {
            let b = YaziBaglami.oku()
            DispatchQueue.main.async {
                guard self.oneriAcik, self.kip == .uygulama, !self.siri, let b else {
                    self.oneriOkunuyor = false
                    self.sonBaglam = nil
                    if self.oneriler.aktif { self.oneriler = Oneriler() }
                    return
                }
                guard b != self.sonBaglam else { self.oneriOkunuyor = false; return }
                self.sonBaglam = b
                Oneriler.iste(b) { o in
                    self.oneriOkunuyor = false
                    if o != self.oneriler { self.oneriler = o }
                }
            }
        }
    }

    private var sonBaglam: YaziBaglami?

    func oneriSec(_ kelime: String) {
        oneriler.sec(kelime)
        sonBaglam = nil
    }

    /// Orijinaldeki ">" tuşu: önerileri gizler/gösterir.
    @Published var oneriKapali = false

    // MARK: kısayollar
    /// ⌘'li kısayolu önce öndeki uygulamanın menüsünden çalıştırır (klavye düzeninden bağımsız); menüde yoksa tuş gönderir.
    func kisayol(_ kod: CGKeyCode, _ bayrak: CGEventFlags = [], _ karakter: String? = nil) {
        guard bayrak.contains(.maskCommand), let karakter, let pid = uygulama?.processIdentifier else {
            Sistem.tus(kod, bayrak, karakter: karakter)
            return
        }
        // klavye düzeninin bu tuşla ürettiği karakter (Türkçe Q'da "[" yerine "ğ")
        let duzen = GirisKaynagi.karakter(kod)
        Sistem.arka.async {
            let shift = bayrak.contains(.maskShift)
            var bulundu = Sistem.menuOgesi(pid, karakter, shift: shift)
            if !bulundu, let duzen, duzen.lowercased() != karakter.lowercased() { bulundu = Sistem.menuOgesi(pid, duzen, shift: shift) }
            Sistem.gunluk("kısayol ⌘\(shift ? "⇧" : "")\(karakter) (düzende \(duzen ?? "?")): \(bulundu ? "menüden" : "tuşla")")
            // menüde yoksa gerçek bir tuş basışı gibi gönder: karakteri zorlamadan, düzen ne üretiyorsa o
            if !bulundu { DispatchQueue.main.async { Sistem.tus(kod, bayrak) } }
        }
    }
}

extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
