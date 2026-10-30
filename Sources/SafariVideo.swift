import AppKit

// Safari'de oynatılan video (YouTube vb.): sayfadaki <video> öğesi AppleScript'in "do JavaScript" komutuyla okunur ve
// yönetilir. Bunun için Safari'de Geliştir → "Apple Event'lerden gelen JavaScript'e izin ver" açık olmalı.
// Küçük resimler YouTube'un kendi kare görsellerinden (storyboard) kesilir; diğer sitelerde şerit küçük resimsizdir.
struct SafariVideo: Equatable {
    var konum: Float
    var sure: Double
    var duraklatildi: Bool
    /// sayfa adresi (değişince küçük resimler yeniden alınır)
    var adres: String
    /// YouTube storyboard tanımı ("…|80#45#…") ya da boş
    var kareler: String

    var gecen: Double { Double(konum) * sure }
}

enum SafariOynatici {
    /// Sayfadaki en büyük, süresi belli video. YouTube'da oyuncunun güncel yanıtından storyboard da alınır.
    private static let okuJS = """
    (function(){var v=[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.duration>0&&isFinite(x.duration)})\
    .sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight})[0];if(!v)return '';var sb='';\
    try{var p=document.querySelector('#movie_player');var r=(p&&p.getPlayerResponse&&p.getPlayerResponse())||window.ytInitialPlayerResponse;\
    sb=r.storyboards.playerStoryboardSpecRenderer.spec}catch(e){}\
    return JSON.stringify({t:v.currentTime,d:v.duration,p:v.paused,u:location.href,sb:sb})})()
    """

    private static func calistir(_ js: String) -> NSAppleEventDescriptor? {
        let kacis = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var hata: NSDictionary?
        let sonuc = NSAppleScript(source: "tell application \"Safari\" to do JavaScript \"\(kacis)\" in current tab of front window")?
            .executeAndReturnError(&hata)
        if let hata, let n = hata[NSAppleScript.errorNumber] as? Int, n != sonHata {
            sonHata = n
            Sistem.gunluk("safari video: JavaScript çalışmadı (\(n)) — Geliştir → Apple Event'lerden gelen JavaScript'e izin ver")
        }
        return sonuc
    }

    private static var sonHata = 0

    /// Arka kuyrukta çağrılır. Video yoksa nil.
    static func oku() -> SafariVideo? {
        guard let s = calistir(okuJS)?.stringValue, let veri = s.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any],
              let t = j["t"] as? Double, let d = j["d"] as? Double, d > 0 else { return nil }
        return SafariVideo(konum: Float(t / d), sure: d, duraklatildi: j["p"] as? Bool ?? true,
                           adres: j["u"] as? String ?? "", kareler: j["sb"] as? String ?? "")
    }

    private static let videoJS = "[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.duration>0})" +
        ".sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight})[0]"

    static func sar(_ saniye: Double) { _ = calistir("(function(){var v=\(videoJS);if(v)v.currentTime=\(saniye)})()") }
    static func oynatDuraklat() { _ = calistir("(function(){var v=\(videoJS);if(v){if(v.paused)v.play();else v.pause()}})()") }

    /// YouTube storyboard'undan eşit aralıklı küçük resimler. Arka kuyrukta çağrılır.
    /// Tanım: "taban_url|g#y#adet#sütun#satır#aralık#ad#imza|…"; taban adreste $L düzey, $N sayfa adı (içinde $M sayfa no).
    static func kucukResimler(_ tanim: String, adet: Int) -> [NSImage] {
        let parca = tanim.components(separatedBy: "|")
        guard parca.count >= 2 else { return [] }
        // 80×45'lik düzey yeterli ve hızlı (ilk düzey 48×27, sonuncusu en büyük)
        let duzey = min(2, parca.count - 1)
        let f = parca[duzey].components(separatedBy: "#")
        guard f.count >= 8, let w = Int(f[0]), let h = Int(f[1]), let toplam = Int(f[2]), let sut = Int(f[3]), let sat = Int(f[4]),
              toplam > 0, sut > 0, sat > 0 else { return [] }
        let sayfaBasina = sut * sat
        var sayfalar: [Int: CGImage] = [:]
        var sonuc: [NSImage] = []
        for i in 0..<adet {
            let k = min(toplam - 1, Int((Double(i) + 0.5) / Double(adet) * Double(toplam)))
            let s = k / sayfaBasina, yer = k % sayfaBasina
            if sayfalar[s] == nil {
                let ad = f[6].replacingOccurrences(of: "$M", with: "\(s)")
                let adres = parca[0].replacingOccurrences(of: "$L", with: "\(duzey - 1)").replacingOccurrences(of: "$N", with: ad)
                    + (f[7].isEmpty ? "" : "&sigh=\(f[7])")
                if let u = URL(string: adres), let veri = try? Data(contentsOf: u),
                   let kaynak = CGImageSourceCreateWithData(veri as CFData, nil),
                   let cg = CGImageSourceCreateImageAtIndex(kaynak, 0, nil) { sayfalar[s] = cg }
            }
            guard let sayfa = sayfalar[s],
                  let kesit = sayfa.cropping(to: CGRect(x: (yer % sut) * w, y: (yer / sut) * h, width: w, height: h)) else { continue }
            sonuc.append(NSImage(cgImage: kesit, size: .zero))
        }
        return sonuc
    }
}
