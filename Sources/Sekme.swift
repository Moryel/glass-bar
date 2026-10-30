import AppKit

// Safari'nin açık pencereleri ve sekmeleri (AppleScript; ilk kullanımda Otomasyon izni sorulur).
struct Sekme: Equatable, Identifiable {
    var pencere: Int
    var sira: Int
    var ad: String
    var adres: String
    var secili: Bool

    var id: String { "\(pencere).\(sira)" }

    /// Arka kuyrukta çağrılır. Satır başına: pencere, sıra, seçili mi, başlık, adres (sekmeyle ayrılmış).
    /// Safari'ye erişilemezse (Otomasyon izni yok) nil.
    static func oku() -> [Sekme]? {
        // Safari'nin içinde `tab` sekme nesnesi demek; ayırıcı olarak sekme karakteri dışarıda tanımlanır
        let betik = """
        set ayr to character id 9
        tell application "Safari"
            set s to ""
            repeat with w from 1 to count windows
                try
                    set pen to window w
                    set ct to index of current tab of pen
                    set i to 0
                    repeat with t in tabs of pen
                        set i to i + 1
                        set u to ""
                        try
                            set u to URL of t
                        end try
                        set ad to ""
                        try
                            set ad to name of t
                        end try
                        set s to s & w & ayr & i & ayr & ((i = ct) as text) & ayr & ad & ayr & u & linefeed
                    end repeat
                end try
            end repeat
            return s
        end tell
        """
        guard let sonuc = Sistem.betik(betik) else { return nil }
        let metin = sonuc.stringValue ?? ""
        var pencereSira: [Int: Int] = [:]
        return metin.split(separator: "\n").compactMap { satir in
            let p = satir.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5, let w = Int(p[0]), let i = Int(p[1]) else { return nil }
            // gizli/boş pencereler atlanınca numaralar 1, 2, 3 diye sıralı kalsın
            let n = pencereSira[w] ?? { let n = pencereSira.count + 1; pencereSira[w] = n; return n }()
            return Sekme(pencere: n, sira: i, ad: p[3], adres: URL(string: p[4])?.host ?? p[4], secili: p[2] == "true")
                .gercekPencere(w)
        }
    }

    /// AppleScript'teki pencere numarası (ekranda gösterilen sıra numarasından farklı olabilir).
    private(set) var asilPencere = 0

    private func gercekPencere(_ w: Int) -> Sekme {
        var s = self
        s.asilPencere = w
        return s
    }

    /// Bu sekmeye geçer ve penceresini öne getirir. Arka kuyrukta çağrılır.
    func sec() {
        Sistem.betik("""
        tell application "Safari"
            set pen to window \(asilPencere)
            set current tab of pen to tab \(sira) of pen
            set index of pen to 1
            activate
        end tell
        """)
    }
}
