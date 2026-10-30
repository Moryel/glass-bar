import SwiftUI

// Çubuğun dizilimi orijinalle aynı: esc | uygulama alanı | Control Strip.
struct Cubuk: View {
    @ObservedObject var d: Durum

    var body: some View {
        // parlaklık/ses kaydırıcısı açıkken çubuğun geri kalanı kararır (orijinaldeki gibi);
        // basılı tutup kaydırırken tuş hiyerarşide kalır ki parmağın hareketi kesilmesin
        let acilir: Durum.Kip? = d.canli ?? ((d.kip == .parlaklik || d.kip == .ses) ? d.kip : nil)
        ZStack {
            Ortam(renk: d.renk, siri: d.siri, stil: d.arkaPlan, resim: d.arkaResim)
            HStack(spacing: Olcu.ara) {
                if d.escGoster {
                    // geçici panel (emoji, sekmeler, Şimdi Oynatılan…) açıkken orijinaldeki gibi "Bitti": paneli kapatır, tuş göndermez
                    let bitti = d.kip == .emoji || d.kip == .sekmeler || d.kip == .simdi
                    Tus(genislik: Olcu.esc, vurgu: bitti ? .white.opacity(0.22) : nil, eylem: bitti ? d.escBasildi : d.esc) {
                        if bitti { Yazi("Bitti") } else { Text("esc").kerning(0.3) }
                    }
                        .transition(.netles)
                }
                Ana(d: d).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 3)
            .opacity(acilir == nil && d.acilir == nil ? 1 : 0)
            // basılı tutup kaydırırken tuş hiyerarşide kalır ki parmağın hareketi kesilmesin
            .allowsHitTesting((acilir == nil && d.acilir == nil) || d.canli != nil || d.acilirKayiyor)
            if let k = acilir {
                AcilirKaydirici(d: d, k: k, kapatilir: d.canli == nil)
                    .transition(.opacity)
            }
            if let a = d.acilir, acilir == nil {
                AcilirGorunum(d: d, a: a)
                    .padding(.horizontal, 3)
                    .transition(.netles)
            }
        }
        .overlay {
            // sıcak ton: beyazı amber'e çeker, siyahı değiştirmez
            let g = d.renkSicakligi.guc(nightShift: d.nightShift)
            if g > 0 {
                Color(red: 1, green: 1 - 0.16 * g, blue: 1 - 0.42 * g)
                    .blendMode(.multiply).allowsHitTesting(false)
            }
        }
        .frame(width: d.genislik, height: Olcu.yukseklik)
        .coordinateSpace(name: "cubuk")
        .background(Color.black)
        .environment(\.tema, d.tema)
        .font(.system(size: 14))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: d.anahtar)
    }
}

/// esc'den sonraki alan: önce geçici paneller, yoksa ayardaki gösterim.
struct Ana: View {
    @ObservedObject var d: Durum

    var body: some View {
        if d.seritDuzenle { SeritDuzenleyici(d: d).transition(.netles) } else { kipler }
    }

    @ViewBuilder private var kipler: some View {
        switch d.kip {
        case .genis: GenisSerit(d: d, kapatilir: true).transition(.netles)
        case .simdi: SimdiSerit(d: d).transition(.netles)
        case .sekmeler: SekmeSerit(d: d).transition(.netles)
        case .emoji: EmojiSerit(d: d).transition(.netles)
        case .uygulama, .parlaklik, .ses:
            if d.ekranAraci != nil && !d.fn {
                Seritli(d: d) { EkranResmiSerit(d: d) }.transition(.netles)
            } else {
            switch d.etkin {
            case .fTuslari: FnSatiri(d: d).transition(.netles)
            case .genis: GenisSerit(d: d, kapatilir: false).transition(.netles)
            case .alanlar: Seritli(d: d) { AlanlarSatiri(d: d) }.transition(.netles)
            case .hizliEylem: Seritli(d: d) { HizliEylemSatiri(d: d) }.transition(.netles)
            case .uygulama: Seritli(d: d) { UygulamaAlani(d: d) }.transition(.netles)
            }
            }
        }
    }
}

/// İçerik + sağda daraltılmış Control Strip; Siri hapı ve basılı kaydırma kaydırıcısı içeriğin üstünde yüzer.
struct Seritli<Icerik: View>: View {
    @ObservedObject var d: Durum
    @ViewBuilder var icerik: () -> Icerik

    var body: some View {
        let ustte = d.siri
        HStack(spacing: Olcu.ara) {
            ZStack {
                icerik()
                    // cam damla arkasını kırarak göstersin diye içerik yalnız hafifçe geri çekilir
                    .blur(radius: ustte ? 1 : 0)
                    .opacity(ustte ? 0.55 : 1)
                    .allowsHitTesting(!ustte)
                if d.siri {
                    Button(action: d.siriKapat) { SiriHap() }
                        .buttonStyle(.plain)
                        .transition(.damla)
                }
            }
            if d.seritGoster { DarSerit(d: d) }
        }
    }
}

/// Camın arkasındaki ışık: salınım Core Animation'da (Katman.swift), dokunuş ışığı SwiftUI'da.
/// Camın arkası (menüde "Arka plan"): kapalıyken yalnız dokunuşta hafif beyaz parıltı; ışık stillerinde yavaşça
/// dolaşan üç renk lekesi; duvar kağıdı/görselde kısılmış görsel şeridi. Siri dinlerken ışık Siri'nin renklerine döner; arka plan kapalıysa hiç ışık yok.
struct Ortam: View {
    let renk: Color
    let siri: Bool
    let stil: ArkaPlan
    let resim: NSImage?
    @ObservedObject private var isik = Isik.ortak

    var body: some View {
        ZStack {
            if stil.resimli, let resim {
                Image(nsImage: resim).resizable()
                    .blur(radius: 1.5)
                    .overlay(Color.black.opacity(0.4))
                if siri { OrtamKatmani(renkler: SiriRenk.hepsi.dropFirst().map { NSColor($0) }).opacity(0.7) }
            } else if stil != .kapali {
                OrtamKatmani(renkler: siri ? SiriRenk.hepsi.dropFirst().map { NSColor($0) } : (stil.renkler ?? [NSColor(renk)]))
            }
            dokunus
        }
        .allowsHitTesting(false)
    }

    /// Dokunulan tuşun arkasında camdan sızan ışık.
    @ViewBuilder private var dokunus: some View {
        if stil == .kapali {
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.12), .white.opacity(0.05), .clear],
                                     center: .center, startRadius: 0, endRadius: 55))
                .frame(width: 110, height: 70)
                .position(isik.konum)
                .opacity(isik.guc)
        } else {
            let c = stil.renkler.map { Color(nsColor: $0[0]) } ?? renk
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), c.opacity(0.6), .clear],
                                     center: .center, startRadius: 0, endRadius: 45))
                .frame(width: 110, height: 70)
                .position(isik.konum)
                .opacity(isik.guc)
                .blur(radius: 8)
                .blendMode(.plusLighter)
        }
    }
}

// MARK: Control Strip
struct SiriTusu: View {
    @ObservedObject var d: Durum
    var body: some View {
        Tus(genislik: Olcu.simge, eylem: d.siriDegistir) { SiriKure(aktif: d.siri) }
    }
}

struct DarSerit: View {
    @ObservedObject var d: Durum
    var body: some View {
        HStack(spacing: Olcu.ara) {
            Tus("chevron.left", genislik: Olcu.dar, eylem: d.genislet)
            if let c = d.calan { SimdiTusu(d: d, c: c).transition(.netles) }
            ForEach(d.seritTuslari, id: \.self) { SeritTusuGorunum(d: d, t: $0) }
        }
    }
}

/// Orijinaldeki "Control Strip'i Özelleştir"in Touch Bar'daki karşılığı: soldaki tuşlar şeritte olanlar
/// (sürükleyerek sırala, dokununca çıkar), sağdakiler eklenebilenler (dokununca sona eklenir).
struct SeritDuzenleyici: View {
    @ObservedObject var d: Durum
    @StateObject private var s = SeritSurukleme()

    var body: some View {
        let digerleri = SeritTusu.allCases.filter { !d.seritTuslari.contains($0) }
        let adim = Olcu.simge + Olcu.ara
        HStack(spacing: Olcu.ara) {
            Tus(genislik: Olcu.esc, vurgu: Color(hex: 0x0A84FF, 0.6), eylem: { d.seritDuzenle = false }) { Yazi("Bitti") }
            HStack(spacing: Olcu.ara) {
                ForEach(d.seritTuslari, id: \.self) { t in
                    let suruklenen = s.tus == t
                    Tus(t.simge, eylem: { d.seritTuslari.removeAll { $0 == t } })
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 10))
                                .foregroundStyle(.white, Color(hex: 0xFF453A)).offset(x: 2, y: -1)
                        }
                        .offset(x: suruklenen ? s.x : 0)
                        .zIndex(suruklenen ? 1 : 0)
                        .scaleEffect(suruklenen ? 1.08 : 1)
                        .simultaneousGesture(DragGesture(minimumDistance: 8)
                            .onChanged { e in
                                s.tus = t
                                s.x = e.translation.width
                                // parmak bir tuş genişliği kayınca yer değiştir
                                guard let i = d.seritTuslari.firstIndex(of: t) else { return }
                                let j = min(max(0, i + Int((s.x / adim).rounded())), d.seritTuslari.count - 1)
                                if j != i {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        d.seritTuslari.move(fromOffsets: [i], toOffset: j > i ? j + 1 : j)
                                    }
                                    s.x -= CGFloat(j - i) * adim
                                }
                            }
                            .onEnded { _ in withAnimation(.spring(response: 0.3)) { s.tus = nil; s.x = 0 } })
                }
            }
            .padding(.horizontal, 4)
            .background(Capsule().fill(.white.opacity(0.08)))
            Text(L(d.seritTuslari.count >= SeritTusu.enFazla ? "Şerit dolu" : "Ekle:"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
            KaydirmaSeridi {
                ForEach(digerleri, id: \.self) { t in
                    Tus(t.simge, eylem: {
                        guard d.seritTuslari.count < SeritTusu.enFazla else { return }
                        d.seritTuslari.append(t)
                    })
                    .seritte()
                    .opacity(d.seritTuslari.count < SeritTusu.enFazla ? 1 : 0.4)
                }
            }
        }
    }
}

final class SeritSurukleme: ObservableObject {
    @Published var tus: SeritTusu?
    @Published var x: CGFloat = 0
}

struct SeritTusuGorunum: View {
    @ObservedObject var d: Durum
    let t: SeritTusu

    var body: some View {
        switch t {
        case .siri: SiriTusu(d: d)
        case .parlaklik:
            Tus("sun.max.fill") { d.seritEylem(.parlaklik) }
                .kaydirinca({ d.canliKaydir(.parlaklik, $0) }, bitince: d.canliBitti)
                .modifier(YerBildir(d: d, k: .parlaklik))
        case .ses:
            Tus(d.sessiz ? "speaker.slash.fill" : "speaker.wave.2.fill") { d.seritEylem(.ses) }
                .kaydirinca({ d.canliKaydir(.ses, $0) }, bitince: d.canliBitti)
                .modifier(YerBildir(d: d, k: .ses))
        case .sessiz: Tus("speaker.slash.fill", vurgu: d.sessiz ? .white.opacity(0.35) : nil) { d.seritEylem(.sessiz) }
        case .nightShift: Tus("moon.stars.fill", vurgu: d.nightShift ? Color(hex: 0xF5A623, 0.6) : nil) { d.seritEylem(.nightShift) }
        case .girisKaynagi: Tus(eylem: { d.seritEylem(.girisKaynagi) }) { Text(d.klavyeAdi).font(.system(size: 12, weight: .semibold)) }
        default: Tus(t.simge) { d.seritEylem(t) }
        }
    }
}

/// Bir şey çalarken şeritte beliren Şimdi Oynatılan tuşu.
struct SimdiTusu: View {
    @ObservedObject var d: Durum
    let c: Calan
    var body: some View {
        Tus(genislik: 52, eylem: { d.kip = .simdi }) {
            HStack(spacing: 4) {
                UygulamaSimgesi(paket: c.kaynak, boyut: 15)
                Image(systemName: c.caliyor ? "pause.fill" : "play.fill").font(.system(size: 11))
            }
        }
    }
}

struct UygulamaSimgesi: View {
    let paket: String
    var boyut: CGFloat = 20
    private static var onbellek: [String: NSImage] = [:]

    private var simge: NSImage? {
        if let s = UygulamaSimgesi.onbellek[paket] { return s }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: paket) else { return nil }
        let s = NSWorkspace.shared.icon(forFile: url.path)
        UygulamaSimgesi.onbellek[paket] = s
        return s
    }

    var body: some View {
        if let simge {
            Image(nsImage: simge).resizable().frame(width: boyut, height: boyut)
        } else {
            Image(systemName: "music.note")
        }
    }
}

struct GenisSerit: View {
    @ObservedObject var d: Durum
    var kapatilir = true
    var body: some View {
        HStack(spacing: Olcu.ara) {
            if kapatilir { Tus("xmark", genislik: Olcu.dar, eylem: d.daralt) }
            Grup(tuslar: [.init(simge: "sun.min.fill") { d.adim(.parlaklikEksi) },
                          .init(simge: "sun.max.fill") { d.adim(.parlaklikArti) }])
            Tus("rectangle.3.group", eylem: Sistem.missionControl)
            Tus("square.grid.3x3.fill", eylem: Sistem.launchpad)
            Grup(tuslar: [.init(simge: "light.min") { d.adim(.klavyeEksi) },
                          .init(simge: "light.max") { d.adim(.klavyeArti) }])
            Grup(tuslar: [.init(simge: "backward.fill") { d.adim(.onceki) },
                          .init(simge: "playpause.fill") { d.adim(.oynat) },
                          .init(simge: "forward.fill") { d.adim(.sonraki) }])
            Grup(tuslar: [.init(simge: "speaker.slash.fill", vurgu: d.sessiz ? .white.opacity(0.3) : nil) { d.sessizDegistir() },
                          .init(simge: "speaker.wave.1.fill") { d.adim(.sesEksi) },
                          .init(simge: "speaker.wave.3.fill") { d.adim(.sesArti) }])
            SiriTusu(d: d)
        }
    }
}

/// Tuşun çubuktaki yerini saklar; açılır kaydırıcı tuşun hemen solunda açılır.
struct YerBildir: ViewModifier {
    let d: Durum
    let k: Durum.Kip
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { d.tusYeri[k] = g.frame(in: .named("cubuk")) }
                .onChange(of: g.frame(in: .named("cubuk"))) { _, r in d.tusYeri[k] = r }
        })
    }
}

/// Parlaklık/ses kaydırıcısı, orijinal ölçülerde: 360 pt'lik kutu tuşun hemen solunda; dokunup
/// bırakınca tuşun yerinde ✕ çıkar, basılı tutup kaydırırken çıkmaz. Çubuğun geri kalanı kararır.
struct AcilirKaydirici: View {
    @ObservedObject var d: Durum
    let k: Durum.Kip
    let kapatilir: Bool
    static let genislik: CGFloat = 360

    var body: some View {
        let parlaklik = k == .parlaklik
        let tus = d.tusYeri[k] ?? CGRect(x: d.genislik - (parlaklik ? 220 : 160), y: 2, width: Olcu.simge, height: Olcu.tus)
        let sag = tus.midX - 28, gen = AcilirKaydirici.genislik
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                // uçtaki simgeler orijinaldeki gibi aynı zamanda bir adım azaltır/artırır
                Image(systemName: parlaklik ? "sun.min.fill" : "speaker.fill").font(.system(size: 12))
                    .frame(width: 30, height: Olcu.tus).contentShape(Rectangle())
                    .onTapGesture { d.kaydiriciAdim(k, -1) }
                if parlaklik {
                    CamKaydirici(deger: $d.parlaklik, dolgu: Color(hex: 0x0A84FF), degisti: d.parlaklikAyarla)
                } else {
                    CamKaydirici(deger: $d.ses, dolgu: Color(hex: 0x0A84FF), degisti: d.sesAyarla)
                }
                Image(systemName: parlaklik ? "sun.max.fill" : "speaker.wave.3.fill").font(.system(size: 14))
                    .frame(width: 30, height: Olcu.tus).contentShape(Rectangle())
                    .onTapGesture { d.kaydiriciAdim(k, 1) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(width: gen, height: Olcu.tus)
            .background(CamZemin())
            .allowsHitTesting(kapatilir)
            .position(x: max(gen / 2 + 3, sag - gen / 2), y: Olcu.yukseklik / 2)
            .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            if kapatilir {
                Tus("xmark", genislik: Olcu.dar, eylem: d.daralt)
                    .position(x: tus.midX, y: Olcu.yukseklik / 2)
                    .transition(.netles)
            }
        }
        .frame(width: d.genislik, height: Olcu.yukseklik)
    }
}

struct FnSatiri: View {
    @ObservedObject var d: Durum
    var body: some View {
        HStack(spacing: Olcu.ara) {
            ForEach(1...12, id: \.self) { i in
                Tus(genislik: nil, eylem: { d.fnTusu(i) }) { Yazi("F\(i)").frame(maxWidth: .infinity) }
            }
        }
    }
}

/// "Masaüstü alanları" gösterimi.
/// Orijinaldeki "Touch Bar gösterir: Hızlı Eylemler": öndeki uygulamanın Servisler menüsündeki etkin öğeler.
final class HizliEylemler: ObservableObject {
    @Published var ogeler: [String]?
}

struct HizliEylemSatiri: View {
    @ObservedObject var d: Durum
    @StateObject private var h = HizliEylemler()
    private var ogeler: [String]? { h.ogeler }
    var body: some View {
        HStack(spacing: Olcu.ara) {
            Tus("gearshape.2", eylem: oku)
            if let ogeler, !ogeler.isEmpty {
                KaydirmaSeridi {
                    ForEach(ogeler, id: \.self) { t in
                        Tus(genislik: nil, eylem: { sec(t) }) {
                            Text(t).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 180)
                        }
                        .seritte()
                    }
                }
            } else {
                Text(L(ogeler == nil ? "Okunuyor…" : "Şu an seçilebilecek bir şey yok"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: oku)
        .onChange(of: d.paket) { _, _ in oku() }
    }

    private func oku() {
        guard let pid = d.uygulama?.processIdentifier else { h.ogeler = []; return }
        Sistem.arka.async {
            let l = AX.altMenu(pid, kimlik: nil, basliklar: ["Servisler", "Services"])
            DispatchQueue.main.async { h.ogeler = l }
        }
    }

    private func sec(_ t: String) {
        guard let pid = d.uygulama?.processIdentifier else { return }
        Sistem.arka.async { AX.altMenuSec(pid, kimlik: nil, basliklar: ["Servisler", "Services"], t) }
    }
}

struct AlanlarSatiri: View {
    @ObservedObject var d: Durum
    var body: some View {
        HStack(spacing: Olcu.ara) {
            Tus("rectangle.3.group", eylem: Sistem.missionControl)
            ForEach(0..<d.alanlar.sayi, id: \.self) { i in
                Tus(genislik: nil, vurgu: i == d.alanlar.simdiki ? .white.opacity(0.28) : nil, eylem: { Alanlar.git(i) }) {
                    Text(String(format: L("Masaüstü %d"), i + 1)).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: Şimdi Oynatılan
struct SimdiSerit: View {
    @ObservedObject var d: Durum
    var body: some View {
        HStack(spacing: Olcu.ara) {
            Tus("xmark", genislik: Olcu.dar, eylem: d.daralt)
            if let c = d.calan {
                Tus(eylem: { Sistem.acPaket(c.kaynak) }) { UygulamaSimgesi(paket: c.kaynak) }
                Oynatici(d: d, c: c)
            }
            SiriTusu(d: d)
        }
    }
}

/// Önceki/oynat/sonraki + videoda küçük resimli film şeridi, müzikte parça çubuğu.
struct Oynatici: View {
    @ObservedObject var d: Durum
    let c: Calan
    var body: some View {
        Grup(tuslar: [.init(simge: c.video ? "gobackward.15" : "backward.fill") { d.calanKomut { $0.onceki() } },
                      .init(simge: c.caliyor ? "pause.fill" : "play.fill") { d.calanKomut { $0.oynatDuraklat() } },
                      .init(simge: c.video ? "goforward.15" : "forward.fill") { d.calanKomut { $0.sonraki() } }],
             tusGenisligi: Olcu.dar + 2)
        if c.video {
            FilmSeridiGorunum(d: d)
            Text(Zaman.yaz(Double(d.calanKonum) * c.sure) + " / " + Zaman.yaz(c.sure))
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        } else {
            ParcaCubugu(d: d, c: c)
            if c.kaynak == Calan.muzik { Tus("heart") { c.begen() } }
        }
    }
}

enum Zaman {
    static func yaz(_ s: Double) -> String {
        let s = Int(max(0, s))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ParcaCubugu: View {
    @ObservedObject var d: Durum
    let c: Calan
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(c.ad).fontWeight(.semibold) + Text(c.sanatci.isEmpty ? "" : "  ·  \(c.sanatci)").foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(Zaman.yaz(Double(d.calanKonum) * c.sure)) / \(Zaman.yaz(c.sure))").monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    .fixedSize()
            }
            .font(.system(size: 10))
            .lineLimit(1)
            CamKaydirici(deger: $d.calanKonum, ince: true, degisti: { d.calanSar($0) }).frame(height: 10)
        }
        .padding(.horizontal, 10)
    }
}

/// QuickTime videosunun küçük resimleri üstünde sarma; oynatma başı sürüklenince cam merceğe dönüşür.
struct FilmSeridiGorunum: View {
    enum Kaynak { case quickTime, foto, safari }
    @ObservedObject var d: Durum
    let kaynak: Kaynak
    @ObservedObject private var film: FilmSeridi
    @StateObject private var b = Basma()

    init(d: Durum, kaynak: Kaynak = .quickTime) {
        self.d = d
        self.kaynak = kaynak
        _film = ObservedObject(wrappedValue: kaynak == .foto ? FilmSeridi.foto : kaynak == .safari ? FilmSeridi.safari : FilmSeridi.ortak)
    }

    private var konum: Float {
        get {
            switch kaynak {
            case .quickTime: d.calanKonum
            case .foto: d.fotoVideo?.konum ?? 0
            case .safari: d.safariVideo?.konum ?? 0
            }
        }
        nonmutating set {
            switch kaynak {
            case .quickTime: d.calanKonum = newValue
            case .foto: d.fotoVideo?.konum = newValue
            case .safari: d.safariVideo?.konum = newValue
            }
        }
    }

    private func sar(_ v: Float, zorla: Bool = false) {
        switch kaynak {
        case .quickTime: d.calanSar(v, zorla: zorla)
        case .foto: d.fotoSar(v, zorla: zorla)
        case .safari: d.safariSar(v, zorla: zorla)
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), x = CGFloat(konum) * w
            let n = max(1, film.resimler.count)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.08))
                    HStack(spacing: 0) {
                        ForEach(Array(film.resimler.enumerated()), id: \.offset) { _, r in
                            Image(nsImage: r).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: w / CGFloat(n), height: 24).clipped()
                        }
                    }
                    // oynatılmış kısım hafif aydınlık, kalanı loş
                    Rectangle().fill(.black.opacity(0.35)).frame(width: max(0, w - x)).offset(x: x)
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                // oynatma başı
                ZStack {
                    Capsule().fill(.white.opacity(b.basili ? 0.1 : 0.9))
                    Capsule().strokeBorder(.white.opacity(0.95), lineWidth: b.basili ? 1.2 : 0)
                    Capsule().fill(LinearGradient(colors: [.white.opacity(b.basili ? 0.5 : 0), .clear], startPoint: .top, endPoint: .center))
                        .padding(2)
                }
                .frame(width: b.basili ? 18 : 3, height: b.basili ? 29 : 28)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .shadow(color: .white.opacity(b.basili ? 0.4 : 0), radius: 6)
                .offset(x: x - (b.basili ? 9 : 1.5))
                .animation(b.basili ? Yay.bas : Yay.birak, value: b.basili)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    b.basili = true
                    withAnimation(Yay.takip) { konum = Float(min(1, max(0, e.location.x / w))) }
                    sar(konum)
                }
                .onEnded { _ in
                    b.basili = false
                    sar(konum, zorla: true)
                })
        }
        .frame(height: Olcu.tus)
    }
}

// MARK: ekran resmi (⇧⌘5)
/// Orijinaldeki gibi: solda üç yakalama ve üç kayıt tuşu (seçili olan aydınlık), sağda "Şuraya kaydet: Masaüstü ›".
/// Kayıt yerine dokununca yerine seçenekler listesi açılır.
struct EkranResmiSerit: View {
    @ObservedObject var d: Durum
    var body: some View {
        let a = d.ekranAraci ?? EkranAraci()
        HStack(spacing: Olcu.ara) {
            if d.hedefListesi {
                Tus("chevron.left", genislik: Olcu.dar) { d.hedefListesi = false }
                Grup(tuslar: EkranAraci.hedefler.map { h in
                    .init(yazi: h, vurgu: h == a.hedef ? .white.opacity(0.25) : nil) { d.ekranHedefi(h) }
                })
                .frame(maxWidth: .infinity)
            } else {
                Grup(tuslar: EkranAraci.yakalama.map { k in
                    .init(simge: k.kimlik, vurgu: !a.video && a.stil == k.stil ? .white.opacity(0.25) : nil) {
                        d.ekranKipi(k.kimlik, stil: k.stil, video: false)
                    }
                }, tusGenisligi: Olcu.simge)
                Grup(tuslar: EkranAraci.kayit.map { k in
                    .init(simge: EkranAraci.simge(k.kimlik), vurgu: a.video && a.stil == k.stil ? .white.opacity(0.25) : nil) {
                        d.ekranKipi(k.kimlik, stil: k.stil, video: true)
                    }
                }, tusGenisligi: Olcu.simge)
                Spacer(minLength: 0)
                Yazi("Şuraya kaydet:", kalinlik: .regular).foregroundStyle(.white.opacity(0.85))
                Tus(genislik: nil, eylem: { d.hedefListesi = true }) {
                    HStack(spacing: 6) {
                        Text(L(a.hedef)).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(minWidth: 90)
                }
            }
        }
    }
}

// MARK: Safari sekmeleri
/// Safari'nin pencereleri ve sekmeleri: birden çok pencere varsa numaralı düğmeler, altta o pencerenin sekmeleri.
/// Sekmeye dokununca ona geçilir; şerit kaydırılır.
struct SekmeSerit: View {
    @ObservedObject var d: Durum
    var body: some View {
        let pencereler = Array(Set(d.sekmeler.map(\.pencere))).sorted()
        let liste = d.sekmeler.filter { $0.pencere == d.sekmePencere }
        HStack(spacing: Olcu.ara) {
            Tus("xmark", genislik: Olcu.dar, eylem: d.daralt)
            if pencereler.count > 1 {
                Grup(tuslar: pencereler.map { p in
                    .init(yazi: "\(p)", vurgu: p == d.sekmePencere ? .white.opacity(0.25) : nil) { d.sekmePencere = p }
                }, tusGenisligi: 28)
            }
            if liste.isEmpty {
                Text(L(d.sekmeOkunuyor ? "Sekmeler okunuyor…"
                     : d.sekmeIzniYok ? "Safari'ye erişim izni yok: Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon"
                     : "Açık Safari penceresi yok"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
                Spacer(minLength: 0)
            } else {
                KaydirmaSeridi {
                    ForEach(liste) { s in
                        Tus(genislik: nil, vurgu: s.secili ? .white.opacity(0.28) : nil, eylem: { d.sekmeSec(s) }) {
                            Text(s.ad.isEmpty ? s.adres : s.ad)
                                .font(.system(size: 12, weight: s.secili ? .semibold : .regular))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 150)
                        }
                        .seritte()
                        .seritteSecili(s.secili)
                    }
                }
                .id(d.sekmePencere)
            }
            Tus("square.grid.2x2") { d.kisayol(42, [.maskCommand, .maskShift], "\\") }
            Tus("plus") { d.kisayol(17, .maskCommand, "t"); d.sekmeleriSonraYenile() }
        }
    }
}

// MARK: emoji
struct EmojiSerit: View {
    @ObservedObject var d: Durum
    var body: some View {
        let kategoriler = Emoji.kategoriler
        let liste = d.emojiKategori == 0 ? Emoji.sik : kategoriler[d.emojiKategori].emojiler
        HStack(spacing: Olcu.ara) {
            Tus("xmark", genislik: Olcu.dar, eylem: d.daralt)
            Grup(tuslar: kategoriler.indices.map { i in
                .init(simge: kategoriler[i].simge, vurgu: i == d.emojiKategori ? .white.opacity(0.25) : nil) { d.emojiKategori = i }
            }, tusGenisligi: 30)
            KaydirmaSeridi {
                ForEach(liste, id: \.self) { e in
                    Text(e).font(.system(size: 19)).frame(width: 34)
                        .modifier(SiviBasma(tur: .kabarcik, kaydirilabilir: true, eylem: { Emoji.kullan(e) }))
                        .frame(height: Olcu.tus)
                }
            }
            .id(d.emojiKategori)
        }
    }
}

// MARK: uygulama alanı
/// Dar alanda (Control Strip'e çok tuş konunca) önce yazılı etiketler simgeye döner, sonra uygulama simgesi gizlenir.
private struct DarAlanAnahtar: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var darAlan: Int {
        get { self[DarAlanAnahtar.self] }
        set { self[DarAlanAnahtar.self] = newValue }
    }
}

struct UygulamaAlani: View {
    @ObservedObject var d: Durum

    var body: some View {
        ViewThatFits(in: .horizontal) {
            alan(0)
            alan(1).environment(\.darAlan, 1)
            alan(2).environment(\.darAlan, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func alan(_ dar: Int) -> some View {
        HStack(spacing: Olcu.ara) {
            // öndeki uygulamanın kendi Touch Bar tuşlarına geçiş: yanlışlıkla dokununca çubuk kapanmasın diye basılı tutunca
            if dar < 2 {
            Tus(genislik: Olcu.simge, eylem: {}) {
                if let simge = d.uygulama?.icon {
                    Image(nsImage: simge).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in d.uygulamaTuslari() })
            }
            switch d.paket {
            case "com.apple.Safari": Safari(d: d)
            case "com.apple.Notes": Notlar(d: d)
            case Calan.muzik, Calan.spotify, Calan.quickTime: OynaticiAlani(d: d)
            case "com.apple.finder": FinderTuslari(d: d)
            case "com.apple.mail": MailTuslari(d: d)
            case "com.apple.calculator": HesapMakinesi(d: d)
            case "com.apple.iCal": TakvimTuslari(d: d)
            case "com.apple.reminders":
                Tus("plus") { d.kisayol(45, .maskCommand, "n") }
                Spacer(minLength: 0)
            case Kisi.paket: KisilerTuslari(d: d)
            case "com.apple.Preview": OnizlemeTuslari(d: d)
            case "com.apple.Photos": FotograflarTuslari(d: d)
            case "com.apple.MobileSMS":
                Tus("square.and.pencil") { d.kisayol(45, .maskCommand, "n") }
                TapbackTusu(d: d)
                YaziAlani(d: d)
            case "com.apple.TextEdit":
                MetinBicimi(d: d)
                YaziAlani(d: d)
            default:
                // yazı alanı odaktayken orijinaldeki gibi: emoji solda, öneriler sağda
                Tus("face.smiling") { d.kip = .emoji }
                if d.oneriler.aktif {
                    Spacer(minLength: 0)
                    OneriSeridi(d: d)
                } else {
                    Text(d.uygulama?.localizedName ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 6)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Yazma önerileri, orijinal ölçülerde: ">" ile gizlenen, 375 pt'lik üç kutu. Yarım kelime varken ilk
/// kutu yazılanın kendisi (tırnak içinde, seçince yalnız boşluk), düzeltme mavi.
struct OneriSeridi: View {
    @ObservedObject var d: Durum
    var body: some View {
        if d.oneriKapali {
            Tus(genislik: 46, eylem: { d.oneriKapali = false }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                    Image(systemName: "keyboard")
                }
            }
        } else {
            HStack(spacing: Olcu.ara) {
                Tus("chevron.right", genislik: Olcu.dar) { d.oneriKapali = true }
                Grup(tuslar: kutular, zemin: Color(hex: 0x2A3A50)).frame(width: 375)
                    .animation(.easeInOut(duration: 0.18), value: d.oneriler)
            }
        }
    }

    private var kutular: [GrupTus] {
        let o = d.oneriler
        var t: [GrupTus] = []
        if !o.yarim.isEmpty { t.append(.init(yazi: "“\(o.yarim)”") { Sistem.yaz(" ") }) }
        for (i, k) in o.kelimeler.enumerated() {
            t.append(.init(yazi: k, vurgu: o.duzeltme && i == 0 ? Color(hex: 0x0A84FF, 0.6) : nil) { d.oneriSec(k) })
        }
        while t.count < 3 { t.append(.init(yazi: "") {}) }
        return t
    }
}

struct OynaticiAlani: View {
    @ObservedObject var d: Durum
    var body: some View {
        if let c = d.calan, c.kaynak == d.paket {
            Oynatici(d: d, c: c)
            if d.paket == Calan.muzik {
                Tus("text.line.first.and.arrowtriangle.forward") { d.menu(nil, "Sıradaki Olarak Çal", "Sonra Çal") }
            }
        } else {
            Text(L(d.paket == Calan.quickTime ? "Açık video yok" : "Çalan parça yok"))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
            Spacer(minLength: 0)
        }
    }
}

struct Safari: View {
    @ObservedObject var d: Durum
    @Environment(\.tema) private var tema
    var body: some View {
        if let v = d.safariVideo {
            SafariVideoSerit(d: d, v: v)
        } else {
            normal
        }
    }

    @ViewBuilder private var normal: some View {
        Grup(tuslar: [.init(simge: "chevron.left") { d.kisayol(33, .maskCommand, "[") },
                      .init(simge: "chevron.right") { d.kisayol(30, .maskCommand, "]") }],
             tusGenisligi: Olcu.dar)
        Tus(genislik: nil, eylem: { d.kisayol(37, .maskCommand, "l") }) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(L("Ara veya web sitesi adı gir")).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Tus("square.on.square", eylem: d.sekmeleriAc)
        // sade temada birincil eylem tonlu (Apple: ton yalnız birincil eyleme)
        Tus("plus", vurgu: tema == .sade ? Color(hex: 0x0A84FF) : nil) { d.kisayol(17, .maskCommand, "t") }
    }
}

/// Safari'de video oynatılırken (orijinaldeki gibi): oynat/duraklat, ±10 sn, küçük resimli sarma şeridi, süre,
/// en sağda adres çubuğu (videodan çıkmadan arama için).
struct SafariVideoSerit: View {
    @ObservedObject var d: Durum
    let v: SafariVideo
    var body: some View {
        Grup(tuslar: [.init(simge: "gobackward.10") { d.safariAtla(-10) },
                      .init(simge: v.duraklatildi ? "play.fill" : "pause.fill") { d.safariOynat() },
                      .init(simge: "goforward.10") { d.safariAtla(10) }],
             tusGenisligi: Olcu.dar + 2)
        FilmSeridiGorunum(d: d, kaynak: .safari)
        Text(Zaman.yaz(v.gecen) + " / " + Zaman.yaz(v.sure))
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        Tus("magnifyingglass") { d.kisayol(37, .maskCommand, "l") }
    }
}

struct Notlar: View {
    @ObservedObject var d: Durum
    var body: some View {
        if d.oneriler.aktif {
            Tus("checklist") { d.menu(nil, "Yapılacaklar Listesi") }
            AcilirTus(d: d, acilir: {
                Acilir(ogeler: [AcilirOge(yazi: "Ana Başlık") { d.menu(nil, "Ana Başlık") },
                                AcilirOge(yazi: "Başlık") { d.menu(nil, "Başlık") },
                                AcilirOge(yazi: "Alt Başlık") { d.menu(nil, "Alt Başlık") },
                                AcilirOge(yazi: "Gövde") { d.menu(nil, "Gövde") },
                                AcilirOge(simge: "bold") { d.kisayol(11, .maskCommand, "b") },
                                AcilirOge(simge: "italic") { d.kisayol(34, .maskCommand, "i") },
                                AcilirOge(simge: "underline") { d.kisayol(32, .maskCommand, "u") }])
            }) { Image(systemName: "textformat") }
            AcilirTus(d: d, acilir: {
                Acilir(ogeler: [AcilirOge(simge: "list.bullet") { d.menu(nil, "Madde İşaretli Liste") },
                                AcilirOge(simge: "list.dash") { d.menu(nil, "Tire İşaretli Liste") },
                                AcilirOge(simge: "list.number") { d.menu(nil, "Numaralı Liste") }])
            }) { Image(systemName: "list.bullet") }
            Tus("face.smiling") { d.kip = .emoji }
            Spacer(minLength: 0)
            OneriSeridi(d: d)
        } else {
            Tus("square.and.pencil") { d.menu(nil, "Yeni Not") }
            Tus("checklist") { d.menu(nil, "Yapılacaklar Listesi") }
            Tus("trash") { d.menu(nil, "Sil") }
            Tus("list.bullet") { d.menu(nil, "Madde İşaretli Liste") }
            Spacer(minLength: 0)
        }
    }
}

/// Orijinaldeki gibi: geri/ileri, görünüm (açılır), ortada Hızlı Bakış, Paylaş, Etiketler (açılır renk paleti).
struct FinderTuslari: View {
    @ObservedObject var d: Durum
    // Finder etiket sırası Sistem.swift'teki Finder.etiket ile aynı
    private let etiketler: [(Color, Int)] = [(Color(hex: 0xFF453A), 2), (Color(hex: 0xFF9F0A), 1), (Color(hex: 0xFFD60A), 3),
                                             (Color(hex: 0x30D158), 6), (Color(hex: 0x0A84FF), 4), (Color(hex: 0xBF5AF2), 5),
                                             (Color(hex: 0x8E8E93), 7)]
    var body: some View {
        Grup(tuslar: [.init(simge: "chevron.left") { d.kisayol(33, .maskCommand, "[") },
                      .init(simge: "chevron.right") { d.kisayol(30, .maskCommand, "]") }],
             tusGenisligi: Olcu.simge)
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: [AcilirOge(simge: "square.grid.2x2") { d.kisayol(18, .maskCommand, "1") },
                            AcilirOge(simge: "list.bullet") { d.kisayol(19, .maskCommand, "2") },
                            AcilirOge(simge: "rectangle.split.3x1") { d.kisayol(20, .maskCommand, "3") },
                            AcilirOge(simge: "squares.below.rectangle") { d.kisayol(21, .maskCommand, "4") }])
        }) { Image(systemName: "square.grid.2x2") }
        Spacer(minLength: 0)
        Tus("eye") { d.kisayol(49) }
        Tus("square.and.arrow.up") { d.menu(nil, "Paylaş…", "Paylaş") }
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: etiketler.map { renk, sira in AcilirOge(nokta: renk) { Finder.etiket(sira) } }
                   + [AcilirOge(simge: "xmark.circle") { Finder.etiket(0) }])
        }) { Image(systemName: "tag") }
        Spacer(minLength: 0)
    }
}

/// Orijinaldeki gibi: Yeni İleti, Yanıtla (basılı tutup kaydırınca Tümünü Yanıtla / İlet), Arşivle,
/// "Şuraya Taşı…" (posta kutuları), Sil, Bayrak (renkler). Menü öğeleri Mail'in dilden bağımsız kimlikleriyle.
struct MailTuslari: View {
    @ObservedObject var d: Durum
    @Environment(\.darAlan) private var dar
    private let m = "Mail.menuBar.messageMenu."
    var body: some View {
        // ileti yazılırken orijinaldeki gibi: Gönder, dosya ekle, sonra yazma önerileri
        if d.oneriler.aktif {
            Tus("paperplane.fill", vurgu: Color(hex: 0x0A84FF, 0.6)) { d.menu(nil, "Gönder") }
            Tus("paperclip") { d.menu(nil, "Dosya Ekle…", "Dosyaları Ekle…") }
            YaziAlani(d: d)
        } else {
            liste
        }
    }

    @ViewBuilder private var liste: some View {
        Tus("square.and.pencil") { d.menu("Mail.menuBar.fileMenu.newMessage") }
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: [AcilirOge(yazi: "Yanıtla") { d.menu(m + "reply") },
                            AcilirOge(yazi: "Tümünü Yanıtla") { d.menu(m + "replyAll") },
                            AcilirOge(yazi: "İlet") { d.menu(m + "forward") }])
        }, dokununca: { d.menu(m + "reply") }) { Image(systemName: "arrowshape.turn.up.left") }
        Tus("archivebox") { d.menu(m + "archive") }
        Tus(genislik: nil, eylem: { d.altMenuAc(m + "moveTo", [], baslik: "Şuraya Taşı") }) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                if dar == 0 { Yazi("Şuraya Taşı…").opacity(0.85) }
            }
        }
        Tus("xmark.bin") { d.menu("Mail.menuBar.editMenu.delete") }
        Tus(eylem: { d.altMenuAc(m + "flag", [], baslik: "Bayrak") }) {
            Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xFF9F0A))
        }
    }
}

/// Orijinaldeki gibi: ± % , solda; ÷ × − + = turuncu. Hesap Makinesi'nin kendi düğmelerine basar.
struct HesapMakinesi: View {
    @ObservedObject var d: Durum
    private let turuncu = Color(hex: 0xFF9F0A, 0.5)
    var body: some View {
        tus("Negate") { Image(systemName: "plus.forwardslash.minus") }
        tus("Percent") { Image(systemName: "percent") }
        tus("Decimal") { Text(",").font(.system(size: 16, weight: .medium)) }
        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        tus("Divide", turuncu) { Image(systemName: "divide") }
        tus("Multiply", turuncu) { Image(systemName: "multiply") }
        tus("Subtract", turuncu) { Image(systemName: "minus") }
        tus("Add", turuncu) { Image(systemName: "plus") }
        tus("Equals", turuncu) { Image(systemName: "equal") }
    }

    private func tus<E: View>(_ kimlik: String, _ renk: Color? = nil, @ViewBuilder _ e: @escaping () -> E) -> some View {
        Tus(genislik: nil, vurgu: renk, eylem: { d.pencereDugmesi(kimlik) }) { e().frame(maxWidth: .infinity) }
    }
}

/// Orijinaldeki gibi: "Bugün" ve aylar arasında kayan şerit; gösterilen ay kırmızı yazılı, çerçeveli.
struct TakvimTuslari: View {
    @ObservedObject var d: Durum
    private static func bicim(_ b: Calendar.Component) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        f.setLocalizedDateFormatFromTemplate(b == .month ? "MMM" : b == .day ? "EEEd" : "dMMM")
        return f
    }

    var body: some View {
        let c = Calendar.current
        let b = d.takvimBirim
        let f = TakvimTuslari.bicim(b)
        let birimler = (b == .day ? -7...30 : -4...20).compactMap { c.date(byAdding: b, value: $0, to: d.takvimAy) }
        Tus(genislik: nil, eylem: d.takvimBugun) { Yazi("Bugün") }
        KaydirmaSeridi {
            ForEach(birimler, id: \.self) { t in
                let secili = c.isDate(t, equalTo: d.takvimAy, toGranularity: b)
                Tus(genislik: b == .month ? 84 : 92, eylem: { d.takvimGit(t) }) {
                    Text(f.string(from: t).replacingOccurrences(of: ".", with: ""))
                        .foregroundStyle(secili ? Color(hex: 0xFF453A) : .white)
                }
                .seritte()
                .overlay(Capsule().strokeBorder(.white, lineWidth: secili ? 1.5 : 0))
            }
        }
        .id("\(d.takvimAy)\(b)")
    }
}

/// Orijinaldeki gibi: yeni kişi, seçili kişinin adıyla mesaj, ara, FaceTime, e-posta, Düzenle, Paylaş.
struct KisilerTuslari: View {
    @ObservedObject var d: Durum
    var body: some View {
        let k = d.kisi
        Tus("plus") { d.kisayol(45, .maskCommand, "n") }
        Tus(genislik: nil, eylem: { k?.mesaj() }) {
            HStack(spacing: 6) {
                Image(systemName: "message")
                Text(k?.ad ?? "").lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(k == nil ? 0.4 : 1)
        Tus("phone") { k?.ara() }.opacity(k?.telefon.isEmpty ?? true ? 0.4 : 1)
        Tus("video") { k?.goruntulu() }.opacity(k == nil ? 0.4 : 1)
        Tus("envelope") { k?.epostaYaz() }.opacity(k?.eposta.isEmpty ?? true ? 0.4 : 1)
        Tus(genislik: nil, eylem: { d.kisayol(37, .maskCommand, "l") }) { Yazi("Düzenle") }
        Tus("square.and.arrow.up") { d.menu(nil, "Kartı Paylaş…", "Kartı Paylaş", "Paylaş…", "Paylaş") }
    }
}

/// Orijinaldeki gibi: solda ayarlar (açılır), ortada sola/sağa döndür, yatay/düşey çevir.
struct OnizlemeTuslari: View {
    @ObservedObject var d: Durum
    var body: some View {
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: [AcilirOge(yazi: "İşaretleme") { d.menu(nil, "İşaretleme Araç Çubuğunu Göster", "İşaretleme Araç Çubuğunu Gizle") },
                            AcilirOge(yazi: "Renk Ayarla") { d.menu(nil, "Renk Ayarla…") },
                            AcilirOge(yazi: "Boyutu Ayarla") { d.menu(nil, "Boyutu Ayarla…") }])
        }) { Image(systemName: "slider.horizontal.3") }
        Spacer(minLength: 0)
        Tus("rotate.left") { d.menu(nil, "Sola Döndür") }
        Tus("rotate.right") { d.menu(nil, "Sağa Döndür") }
        Tus(eylem: { d.menu(nil, "Yatay Olarak Çevir") }) { Image(systemName: "flip.horizontal") }
        Tus(eylem: { d.menu(nil, "Düşey Olarak Çevir") }) { Image(systemName: "flip.horizontal").rotationEffect(.degrees(90)) }
        Spacer(minLength: 0)
    }
}

/// Orijinaldeki gibi: Favori, Otomatik İyileştir, Döndür; video açıkken oynat/duraklat ve videonun karelerinden
/// oluşan küçük resimli şerit (oynatma başını sürükleyerek sarma). Düğmeler Fotoğraflar'ın araç çubuğundakiler.
struct FotograflarTuslari: View {
    @ObservedObject var d: Durum
    var body: some View {
        Tus("heart") { d.pencereDugmesi("IPXToolbarItemIDFavorite") }
        Tus("wand.and.rays") { d.pencereDugmesi("IPXToolbarItemIDAutoEnhance") }
        Tus("rotate.left") { d.pencereDugmesi("IPXToolbarItemIDRotate") }
        if let v = d.fotoVideo {
            Tus("playpause.fill") { d.pencereDugmesi("button_playPause") }
            FilmSeridiGorunum(d: d, kaynak: .foto)
            Text(v.gecen + " / " + v.kalan.filter { $0 != "\u{200E}" })
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize()
        } else {
            Spacer(minLength: 0)
        }
    }
}

/// Mesajlar: seçili iletiye Tapback (basılı tutup kaydırarak da seçilir).
struct TapbackTusu: View {
    @ObservedObject var d: Durum
    var body: some View {
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: ["❤️", "👍", "👎", "😂", "‼️", "❓"].enumerated().map { i, e in
                AcilirOge(yazi: e) { d.tapback(i + 1) }
            })
        }) { Image(systemName: "hand.thumbsup") }
    }
}

/// TextEdit: kalın/italik/altı çizili ve hizalama.
struct MetinBicimi: View {
    @ObservedObject var d: Durum
    var body: some View {
        AcilirTus(d: d, acilir: {
            Acilir(ogeler: [AcilirOge(simge: "bold") { d.kisayol(11, .maskCommand, "b") },
                            AcilirOge(simge: "italic") { d.kisayol(34, .maskCommand, "i") },
                            AcilirOge(simge: "underline") { d.kisayol(32, .maskCommand, "u") },
                            AcilirOge(simge: "text.alignleft") { d.menu(nil, "Sola Hizala") },
                            AcilirOge(simge: "text.aligncenter") { d.menu(nil, "Ortala") },
                            AcilirOge(simge: "text.alignright") { d.menu(nil, "Sağa Hizala") },
                            AcilirOge(simge: "text.justify") { d.menu(nil, "İki Yana Yasla") }])
        }) { Image(systemName: "textformat") }
    }
}

/// Yazı yazılan uygulamalarda: emoji, yazarken öneriler, yazmıyorken uygulamanın adı.
struct YaziAlani: View {
    @ObservedObject var d: Durum
    var body: some View {
        Tus("face.smiling") { d.kip = .emoji }
        if d.oneriler.aktif {
            Spacer(minLength: 0)
            OneriSeridi(d: d)
        } else {
            Text(d.uygulama?.localizedName ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
    }
}
