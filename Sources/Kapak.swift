import AppKit
import SwiftUI

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

        SesDalgasi(caliyor: c.caliyor, renkler: kapak.renkler).frame(width: 62, height: 20).padding(.trailing, 4)
    }
}

/// Kapak renklerinde çubuklar. Ses yakalama açıksa Spotify'ın sesinin frekans bantlarıyla oynar (soldan sağa bas → tiz);
/// izin yoksa çalarken temsili dalgalanır. Duraklatınca dinlenir.
struct SesDalgasi: View {
    let caliyor: Bool
    let renkler: [Color]
    @ObservedObject private var ses = SesYakalayici.ortak
    private let adet = SesYakalayici.bantSayisi

    var body: some View {
        if !caliyor {
            cubuklar([Double](repeating: 0, count: adet))
        } else if ses.calisiyor {
            CanliCubuklar(renkler: renkler)
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

/// Gerçek sesle oynayan çubuklar: SesYakalayici'nin her ölçümü doğrudan CALayer çerçevelerine yazılır.
struct CanliCubuklar: NSViewRepresentable {
    let renkler: [Color]

    func makeNSView(context: Context) -> CubukGorunumu {
        let v = CubukGorunumu()
        SesYakalayici.ortak.dinleyici = { [weak v] in v?.ciz($0) }
        return v
    }

    func updateNSView(_ v: CubukGorunumu, context: Context) {
        v.renkler = renkler.map { NSColor($0).cgColor }
    }
}

final class CubukGorunumu: NSView {
    private let adet = SesYakalayici.bantSayisi
    private var katmanlar: [CALayer] = []
    private var son: [Float]
    var renkler: [CGColor] = [] {
        didSet {
            guard !renkler.isEmpty else { return }
            for (i, k) in katmanlar.enumerated() { k.backgroundColor = renkler[i * renkler.count / adet] }
        }
    }

    init() {
        son = [Float](repeating: 0, count: adet)
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<adet {
            let k = CALayer()
            layer?.addSublayer(k)
            katmanlar.append(k)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        ciz(son)
    }

    func ciz(_ seviyeler: [Float]) {
        son = seviyeler
        let ara: CGFloat = 1.5
        let w = (bounds.width - ara * CGFloat(adet - 1)) / CGFloat(adet)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, k) in katmanlar.enumerated() {
            let h = 4 + (bounds.height - 4) * CGFloat(seviyeler[i])
            k.frame = CGRect(x: CGFloat(i) * (w + ara), y: (bounds.height - h) / 2, width: w, height: h)
            k.cornerRadius = w / 2
        }
        CATransaction.commit()
    }
}
