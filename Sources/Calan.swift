import AppKit
import AVFoundation

// Şimdi Oynatılan: Müzik, Spotify ve QuickTime'dan çalanı AppleScript ile okur ve yönetir.
// (Genel "şimdi oynatılan" bilgisi MediaRemote'ta; macOS 15.4'ten beri üçüncü taraf uygulamalara kapalı.)
struct Calan: Equatable {
    var kaynak: String
    var ad: String
    var sanatci: String
    var konum: Double
    var sure: Double
    var caliyor: Bool
    var dosya: String?
    /// Spotify'da kapak resminin adresi.
    var kapak: String? = nil

    static let muzik = "com.apple.Music", spotify = "com.spotify.client", quickTime = "com.apple.QuickTimePlayerX"
    static let kaynaklar = [muzik, spotify, quickTime]

    var video: Bool { kaynak == Calan.quickTime }

    /// Çalışan kaynaklardan önce öndeki uygulamanınki, sonra çalan, sonra duraklatılmış olan.
    /// Arka kuyrukta çağrılır; `calisan` ana iş parçacığında toplanır.
    static func oku(onde: String, calisan: Set<String>) -> Calan? {
        let adaylar = kaynaklar.filter(calisan.contains).compactMap(oku(kaynak:))
        return adaylar.first { $0.kaynak == onde } ?? adaylar.first(where: \.caliyor) ?? adaylar.first
    }

    private static func oku(kaynak: String) -> Calan? {
        let betik: String
        switch kaynak {
        case muzik, spotify:
            let uyg = kaynak == muzik ? "Music" : "Spotify"
            let sure = kaynak == muzik ? "duration of current track" : "(duration of current track) / 1000"
            betik = """
            tell application "\(uyg)"
                if player state is stopped then return {}
                return {name of current track, artist of current track, player position, \(sure), (player state is playing), \(kaynak == spotify ? "artwork url of current track" : "\"\"")}
            end tell
            """
        default:
            betik = """
            tell application "QuickTime Player"
                if (count documents) = 0 then return {}
                set d to document 1
                set yol to ""
                try
                    set yol to POSIX path of (file of d as alias)
                end try
                return {name of d, "", current time of d, duration of d, playing of d, yol}
            end tell
            """
        }
        guard let d = Sistem.betik(betik), d.numberOfItems == 6 else { return nil }
        let yol = d.atIndex(6)?.stringValue ?? ""
        return Calan(kaynak: kaynak, ad: d.atIndex(1)?.stringValue ?? "", sanatci: d.atIndex(2)?.stringValue ?? "",
                     konum: d.atIndex(3)?.doubleValue ?? 0, sure: max(1, d.atIndex(4)?.doubleValue ?? 1),
                     caliyor: d.atIndex(5)?.booleanValue ?? false,
                     dosya: yol.isEmpty || kaynak == spotify ? nil : yol, kapak: kaynak == spotify && !yol.isEmpty ? yol : nil)
    }

    private var uygAdi: String { kaynak == Calan.muzik ? "Music" : kaynak == Calan.spotify ? "Spotify" : "QuickTime Player" }

    func oynatDuraklat() {
        Sistem.betikArka(video
            ? "tell application \"QuickTime Player\" to tell document 1 to if playing then pause else play"
            : "tell application \"\(uygAdi)\" to playpause")
    }

    /// Videoda 15 sn ileri/geri, müzikte sonraki/önceki parça.
    func sonraki() {
        Sistem.betikArka(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(min(sure, konum + 15))"
                           : "tell application \"\(uygAdi)\" to next track")
    }

    func onceki() {
        Sistem.betikArka(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(max(0, konum - 15))"
                           : "tell application \"\(uygAdi)\" to previous track")
    }

    func git(_ saniye: Double) {
        Sistem.betikArka(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(saniye)"
                           : "tell application \"\(uygAdi)\" to set player position to \(saniye)")
    }

    func begen() {
        guard kaynak == Calan.muzik else { return }
        Sistem.betikArka("""
        tell application "Music"
            try
                set favorited of current track to true
            on error
                set loved of current track to true
            end try
        end tell
        """)
    }
}

/// Videonun küçük resimleri (orijinalde AVKit'in film şeridi).
final class FilmSeridi: ObservableObject {
    static let ortak = FilmSeridi()
    /// Fotoğraflar'da açık videonun küçük resimleri (QuickTime'ınkiyle karışmasın diye ayrı)
    static let foto = FilmSeridi()
    /// Safari'de oynatılan videonun (YouTube) küçük resimleri
    static let safari = FilmSeridi()
    static let adet = 16
    @Published var resimler: [NSImage] = []
    private var yol: String?

    /// Hazır küçük resimler (YouTube storyboard'u); `anahtar` aynıysa yeniden yüklenmez.
    func ayarla(_ r: [NSImage], anahtar: String) {
        yol = anahtar
        resimler = r
    }

    func yukle(_ yol: String?) {
        guard yol != self.yol else { return }
        self.yol = yol
        resimler = []
        guard let yol else { return }
        let varlik = AVURLAsset(url: URL(fileURLWithPath: yol))
        let uretici = AVAssetImageGenerator(asset: varlik)
        uretici.appliesPreferredTrackTransform = true
        uretici.maximumSize = CGSize(width: 140, height: 80)
        Task {
            guard let sure = try? await varlik.load(.duration).seconds, sure > 0 else { return }
            var r: [NSImage] = []
            for i in 0..<FilmSeridi.adet {
                let t = CMTime(seconds: sure * (Double(i) + 0.5) / Double(FilmSeridi.adet), preferredTimescale: 600)
                if let (cg, _) = try? await uretici.image(at: t) { r.append(NSImage(cgImage: cg, size: .zero)) }
            }
            let son = r
            await MainActor.run { if self.yol == yol { self.resimler = son } }
        }
    }
}
