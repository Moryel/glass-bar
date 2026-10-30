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
            Text(Zaman.yaz(Double(d.calanKonum) * c.sure))
            CamKaydirici(deger: $d.calanKonum, ince: true, degisti: { d.calanSar($0) }).frame(height: 10)
            Text("-" + Zaman.yaz(c.sure * (1 - Double(d.calanKonum))))
        }
        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)

        SesDalgasi(caliyor: c.caliyor, renkler: kapak.renkler).frame(width: 62, height: 20).padding(.trailing, 4)
    }
}

/// Kapak renklerinde, çalarken dalgalanan, duraklatınca dinlenen çubuklar.
struct SesDalgasi: View {
    let caliyor: Bool
    let renkler: [Color]
    private let adet = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !caliyor)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<adet, id: \.self) { i in
                    let x = Double(i)
                    let dalga = abs(sin(t * (3.1 + x * 0.37) + x * 1.7) * 0.6 + sin(t * (5.3 + x * 0.21) + x) * 0.4)
                    Capsule()
                        .fill(renkler[i * renkler.count / adet])
                        .frame(height: caliyor ? 4 + 16 * dalga : 4)
                }
            }
            .animation(.easeOut(duration: 0.25), value: caliyor)
        }
    }
}
