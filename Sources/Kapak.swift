import AppKit
import SwiftUI

// MARK: Spotify oynatıcısı ayarları (Spotiw'deki kişiselleştirmeler)

protocol Secenek: RawRepresentable, CaseIterable where RawValue == String {
    var ad: String { get }
}

enum SpotifyYeri: String, Secenek {
    case spotify, masaustu, her
    var ad: String { L(["spotify": "Yalnız Spotify öndeyken", "masaustu": "Masaüstünde de", "her": "Her uygulamada"][rawValue]!) }
}

enum DalgaStili: String, Secenek {
    case cubuk, dalga, nokta
    var ad: String { L(["cubuk": "Çubuklar", "dalga": "Dalga", "nokta": "Noktalar"][rawValue]!) }
}

enum DalgaRengi: String, Secenek {
    case kapak, yesil, beyaz, mavi, mor, turuncu
    var ad: String {
        L(["kapak": "Kapak renkleri", "yesil": "Spotify yeşili", "beyaz": "Beyaz", "mavi": "Mavi", "mor": "Mor", "turuncu": "Turuncu"][rawValue]!)
    }
    var renk: Color? {
        switch self {
        case .kapak: nil
        case .yesil: Color(hex: 0x1DB954)
        case .beyaz: .white
        case .mavi: Color(hex: 0x3D8BFF)
        case .mor: Color(hex: 0x9B5CFF)
        case .turuncu: Color(hex: 0xFF6A3D)
        }
    }
}

enum DalgaGenisligi: String, Secenek {
    case dar, orta, genis, cokGenis
    var ad: String { L(["dar": "Dar", "orta": "Orta", "genis": "Geniş", "cokGenis": "Çok geniş"][rawValue]!) }
    var pt: CGFloat { ["dar": 40, "orta": 62, "genis": 110, "cokGenis": 180][rawValue]! }
}

/// Ses dalgasının ne kadar kolay tepki verdiği: ölçek aralığı (dB); dar aralık küçük değişimleri büyütür.
enum Hassasiyet: String, Secenek {
    case dusuk, normal, yuksek
    var ad: String { L(["dusuk": "Düşük", "normal": "Normal", "yuksek": "Yüksek"][rawValue]!) }
    var aralik: Float { ["dusuk": 32, "normal": 24, "yuksek": 16][rawValue]! }
}

/// Çubukların inişi: her ölçümde önceki seviyenin ne kadarı kalır.
enum Yumusaklik: String, Secenek {
    case az, normal, cok
    var ad: String { L(["az": "Az", "normal": "Normal", "cok": "Çok"][rawValue]!) }
    var dusus: Float { ["az": 0.6, "normal": 0.8, "cok": 0.9][rawValue]! }
}

/// Spotify'da çalan parçanın kapağı ve kapaktan çıkan renkler (ses dalgası bu renklerle boyanır).
/// Kapak, parça değişince Spotify'ın verdiği adresten bir kez indirilir.
final class Kapak: ObservableObject {
    static let ortak = Kapak()
    @Published private(set) var resim: NSImage?
    @Published private(set) var renkler: [Color] = [Color(hex: 0x1DB954)]
    private var adres: String?

    func yukle(_ yeni: String?) {
        guard yeni != adres else { return }
        adres = yeni
        guard let yeni, let url = URL(string: yeni) else { resim = nil; return }
        URLSession.shared.dataTask(with: url) { [weak self] veri, _, _ in
            guard let veri, let resim = NSImage(data: veri) else { return }
            let renkler = Kapak.palet(veri)
            DispatchQueue.main.async {
                guard let self, self.adres == yeni else { return }
                self.resim = resim
                if !renkler.isEmpty { self.renkler = renkler }
            }
        }.resume()
    }

    /// Kapağın en sık görülen renkleri; Touch Bar siyah olduğu için koyu renkler açılır.
    private static func palet(_ veri: Data, adet: Int = 5) -> [Color] {
        guard let kaynak = CGImageSourceCreateWithData(veri as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(kaynak, 0, nil) else { return [] }
        let k = 24
        guard let c = CGContext(data: nil, width: k, height: k, bitsPerComponent: 8, bytesPerRow: k * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(c.draw(img, in: CGRect(x: 0, y: 0, width: k, height: k))),
              let tampon = c.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        var kovalar: [Int: Int] = [:]
        for i in 0..<(k * k) {
            let r = Int(tampon[i * 4]), g = Int(tampon[i * 4 + 1]), b = Int(tampon[i * 4 + 2])
            kovalar[(r / 64) << 4 | (g / 64) << 2 | (b / 64), default: 0] += 1
        }
        return kovalar.sorted { $0.value > $1.value }.prefix(adet).map { kova, _ in
            let renk = NSColor(deviceRed: CGFloat((kova >> 4) & 3) * 64 / 255 + 0.125,
                               green: CGFloat((kova >> 2) & 3) * 64 / 255 + 0.125,
                               blue: CGFloat(kova & 3) * 64 / 255 + 0.125, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, p: CGFloat = 0, a: CGFloat = 0
            renk.getHue(&h, saturation: &s, brightness: &p, alpha: &a)
            return Color(nsColor: p < 0.6 ? NSColor(deviceHue: h, saturation: min(s, 0.8), brightness: 0.6 + p * 0.3, alpha: 1) : renk)
        }
    }
}

/// Spotify çalarken uygulama alanı (Spotiw'in düzeni): kapak, parça adı ve sanatçı, önceki/oynat/sonraki,
/// süreli sarma çubuğu ve kapak renklerinde ses dalgası.
struct SpotifyOynatici: View {
    @ObservedObject var d: Durum
    let c: Calan
    @ObservedObject private var kapak = Kapak.ortak

    var body: some View {
        HStack(spacing: 7) {
            if d.kapakGoster {
            Group {
                if let resim = kapak.resim {
                    Image(nsImage: resim).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.1))
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(c.ad).font(.system(size: 11.5, weight: .semibold))
                Text(c.sanatci).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .opacity(c.caliyor ? 1 : 0.6)
            .frame(width: 118, alignment: .leading)
        }
        .padding(.leading, 4)
        .contentShape(Rectangle())
        .onTapGesture { Sistem.acPaket(c.kaynak) }

        Grup(tuslar: [.init(simge: "backward.fill") { d.calanKomut { $0.onceki() } },
                      .init(simge: c.caliyor ? "pause.fill" : "play.fill") { d.calanKomut { $0.oynatDuraklat() } },
                      .init(simge: "forward.fill") { d.calanKomut { $0.sonraki() } }],
             tusGenisligi: Olcu.dar + 2)

        HStack(spacing: 6) {
            // Touch Bar'da fixedSize yazının sonunu kestiği için süreler sabit genişlikte
            Text(Zaman.yaz(Double(d.calanKonum) * c.sure)).frame(width: 34, alignment: .trailing)
            CamKaydirici(deger: $d.calanKonum, ince: true, degisti: { d.calanSar($0) }).frame(height: 10)
            Text("-" + Zaman.yaz(c.sure * (1 - Double(d.calanKonum)))).frame(width: 38, alignment: .leading)
        }
        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)

        SesDalgasi(caliyor: c.caliyor, renkler: d.dalgaRengi.renk.map { [$0] } ?? kapak.renkler, stil: d.dalgaStili)
            .frame(width: d.dalgaGenisligi.pt, height: 20).padding(.trailing, 4)
    }
}

/// Kapak renklerinde çubuklar. Ses yakalama açıksa Spotify'ın sesinin frekans bantlarıyla oynar (soldan sağa bas → tiz);
/// izin yoksa çalarken temsili dalgalanır. Duraklatınca dinlenir.
struct SesDalgasi: View {
    let caliyor: Bool
    let renkler: [Color]
    var stil: DalgaStili = .cubuk
    @ObservedObject private var ses = SesYakalayici.ortak
    private let adet = SesYakalayici.bantSayisi

    var body: some View {
        if !caliyor {
            cubuklar([Double](repeating: 0, count: adet))
        } else if ses.calisiyor {
            CanliCubuklar(renkler: renkler, stil: stil)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                cubuklar((0..<adet).map { i in
                    let x = Double(i)
                    return abs(sin(t * (3.1 + x * 0.37) + x * 1.7) * 0.6 + sin(t * (5.3 + x * 0.21) + x) * 0.4)
                })
            }
        }
    }

    /// Her karede 14 ayrı görünüm yerine tek Canvas: işlemci yükü belirgin biçimde düşer.
    private func cubuklar(_ seviyeler: [Double]) -> some View {
        let renkler = renkler, adet = adet
        return Canvas { ctx, boyut in
            let ara: CGFloat = 1.5
            let w = (boyut.width - ara * CGFloat(adet - 1)) / CGFloat(adet)
            for i in 0..<adet {
                let h = 4 + (boyut.height - 4) * CGFloat(seviyeler[i])
                let r = CGRect(x: CGFloat(i) * (w + ara), y: (boyut.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(renkler[i * renkler.count / adet]))
            }
        }
    }
}

/// Gerçek sesle oynayan dalga: SesYakalayici'nin her ölçümü doğrudan CALayer'lara yazılır.
struct CanliCubuklar: NSViewRepresentable {
    let renkler: [Color]
    let stil: DalgaStili

    func makeNSView(context: Context) -> CubukGorunumu {
        let v = CubukGorunumu()
        SesYakalayici.ortak.dinleyici = { [weak v] in v?.ciz($0) }
        return v
    }

    func updateNSView(_ v: CubukGorunumu, context: Context) {
        v.stil = stil
        v.renkler = renkler.map { NSColor($0).cgColor }
    }
}

/// Üç stil: çubuklar (ortadan büyüyen kapsüller), noktalar (üst üste noktalar), dalga (bantlardan geçen dolu eğri).
final class CubukGorunumu: NSView {
    private let adet = SesYakalayici.bantSayisi
    private let noktaSayisi = 5
    private var katmanlar: [CALayer] = []
    private let egim = CAGradientLayer()
    private let egri = CAShapeLayer()
    private var son: [Float]
    var stil: DalgaStili = .cubuk { didSet { if stil != oldValue { kur() } } }
    var renkler: [CGColor] = [] { didSet { renkleriUygula() } }

    init() {
        son = [Float](repeating: 0, count: adet)
        super.init(frame: .zero)
        wantsLayer = true
        egim.startPoint = CGPoint(x: 0, y: 0.5)
        egim.endPoint = CGPoint(x: 1, y: 0.5)
        egim.mask = egri
        kur()
    }

    required init?(coder: NSCoder) { nil }

    private func kur() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        katmanlar = []
        if stil == .dalga {
            layer?.addSublayer(egim)
        } else {
            for _ in 0..<(stil == .nokta ? adet * noktaSayisi : adet) {
                let k = CALayer()
                layer?.addSublayer(k)
                katmanlar.append(k)
            }
        }
        renkleriUygula()
        ciz(son)
    }

    private func renkleriUygula() {
        guard !renkler.isEmpty else { return }
        let bantRengi = { (i: Int) in self.renkler[i * self.renkler.count / self.adet] }
        if stil == .dalga {
            egim.colors = renkler.count > 1 ? renkler : [renkler[0], renkler[0]]
        } else {
            let grup = stil == .nokta ? noktaSayisi : 1
            for (j, k) in katmanlar.enumerated() { k.backgroundColor = bantRengi(j / grup) }
        }
    }

    override func layout() {
        super.layout()
        ciz(son)
    }

    func ciz(_ seviyeler: [Float]) {
        son = seviyeler
        let b = bounds, ara: CGFloat = 1.5
        let w = (b.width - ara * CGFloat(adet - 1)) / CGFloat(adet)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch stil {
        case .cubuk:
            for (i, k) in katmanlar.enumerated() {
                let h = 4 + (b.height - 4) * CGFloat(seviyeler[i])
                k.frame = CGRect(x: CGFloat(i) * (w + ara), y: (b.height - h) / 2, width: w, height: h)
                k.cornerRadius = w / 2
            }
        case .nokta:
            let d = min(w, (b.height - CGFloat(noktaSayisi - 1)) / CGFloat(noktaSayisi))
            for i in 0..<adet {
                // ortadan dışa doğru yanan noktalar; ortadaki hep yanık
                let yanan = 1 + Int((CGFloat(seviyeler[i]) * CGFloat(noktaSayisi - 1)).rounded())
                for j in 0..<noktaSayisi {
                    let k = katmanlar[i * noktaSayisi + j]
                    let sira = abs(j - noktaSayisi / 2) * 2 + (j < noktaSayisi / 2 ? 1 : 0)
                    k.frame = CGRect(x: CGFloat(i) * (w + ara) + (w - d) / 2,
                                     y: (b.height - d) / 2 + CGFloat(j - noktaSayisi / 2) * (d + 1), width: d, height: d)
                    k.cornerRadius = d / 2
                    k.opacity = sira < yanan ? 1 : 0.15
                }
            }
        case .dalga:
            egim.frame = b
            let orta = b.height / 2
            let ust = (0..<adet).map { i in
                CGPoint(x: CGFloat(i) * (w + ara) + w / 2, y: orta + 1 + (orta - 1) * CGFloat(seviyeler[i]))
            }
            let yol = CGMutablePath()
            yol.move(to: CGPoint(x: 0, y: orta))
            Self.yumusak(yol, ust)
            yol.addLine(to: CGPoint(x: b.width, y: orta))
            Self.yumusak(yol, ust.reversed().map { CGPoint(x: $0.x, y: 2 * orta - $0.y) })
            yol.closeSubpath()
            egri.path = yol
        }
        CATransaction.commit()
    }

    /// Noktalardan geçen yumuşak eğri: her iki noktanın ortasına, öncekini kontrol noktası alarak.
    private static func yumusak(_ yol: CGMutablePath, _ p: [CGPoint]) {
        guard let ilk = p.first, let son = p.last else { return }
        yol.addLine(to: ilk)
        for i in 1..<p.count {
            yol.addQuadCurve(to: CGPoint(x: (p[i - 1].x + p[i].x) / 2, y: (p[i - 1].y + p[i].y) / 2), control: p[i - 1])
        }
        yol.addLine(to: son)
    }
}
