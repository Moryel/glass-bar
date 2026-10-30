import AppKit

// Kişiler'de seçili kişi (AppleScript; ilk kullanımda Otomasyon izni sorulur). Çubukta ad, ara, FaceTime, mesaj, e-posta.
struct Kisi: Equatable {
    var ad: String
    var telefon: String
    var eposta: String

    static let paket = "com.apple.AddressBook"

    /// Arka kuyrukta çağrılır.
    static func oku() -> Kisi? {
        let betik = """
        set ayr to character id 10
        tell application "Contacts"
            set s to selection
            if (count s) = 0 then return ""
            set p to item 1 of s
            set tel to ""
            try
                set tel to value of first phone of p
            end try
            set ep to ""
            try
                set ep to value of first email of p
            end try
            return (name of p) & ayr & tel & ayr & ep
        end tell
        """
        guard let m = Sistem.betik(betik)?.stringValue, !m.isEmpty else { return nil }
        let p = m.components(separatedBy: "\n")
        guard p.count == 3 else { return nil }
        return Kisi(ad: p[0], telefon: p[1], eposta: p[2])
    }

    private var numara: String { telefon.filter { $0.isNumber || $0 == "+" } }

    func mesaj() { ac("imessage://\(numara.isEmpty ? eposta : numara)") }
    func ara() { if !numara.isEmpty { ac("facetime-audio://\(numara)") } }
    func goruntulu() { ac("facetime://\(numara.isEmpty ? eposta : numara)") }
    func epostaYaz() { if !eposta.isEmpty { ac("mailto:\(eposta)") } }

    private func ac(_ s: String) {
        guard let u = URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? s) else { return }
        NSWorkspace.shared.open(u)
    }
}
