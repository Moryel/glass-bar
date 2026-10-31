import AppKit

/// GitHub'daki son sürümü denetler: açılıştan biraz sonra ve günde bir kez. Daha yeni bir sürüm varsa
/// menünün başında "Güncelleme var" satırı çıkar; tıklayınca sürüm sayfası açılır (indirip kurmak kullanıcıda).
final class Guncelleme {
    static let ortak = Guncelleme()
    static let depo = "Moryel/glass-bar"
    static var surum: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private(set) var yeniSurum: String?
    private(set) var sayfa: URL?
    private var zamanlayici: Timer?

    func baslat() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.denetle() }
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.denetle() }
    }

    /// `elle`: menüden istendiyse sonucu bir pencereyle bildirir.
    func denetle(elle: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.depo)/releases/latest") else { return }
        var istek = URLRequest(url: url)
        istek.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: istek) { veri, _, _ in
            let json = veri.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let etiket = (json?["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let sayfa = (json?["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                if let etiket, etiket.compare(Self.surum, options: .numeric) == .orderedDescending {
                    self.yeniSurum = etiket
                    self.sayfa = sayfa
                    Sistem.gunluk("güncelleme: \(etiket) var (bu sürüm \(Self.surum))")
                } else {
                    self.yeniSurum = nil
                }
                if elle { self.bildir(denetlendi: etiket != nil) }
            }
        }.resume()
    }

    func sayfayiAc() {
        NSWorkspace.shared.open(sayfa ?? URL(string: "https://github.com/\(Self.depo)/releases/latest")!)
    }

    private func bildir(denetlendi: Bool) {
        let uyari = NSAlert()
        if let yeniSurum {
            uyari.messageText = String(format: L("GlassBar %@ çıktı"), yeniSurum)
            uyari.informativeText = String(format: L("Kullandığın sürüm %@. İndirme sayfası açılsın mı?"), Self.surum)
            uyari.addButton(withTitle: L("İndir"))
            uyari.addButton(withTitle: L("Sonra"))
        } else {
            uyari.messageText = denetlendi ? L("GlassBar güncel") : L("Güncellemeler denetlenemedi")
            uyari.informativeText = denetlendi ? String(format: L("Kullandığın sürüm %@ en yenisi."), Self.surum)
                                               : L("İnternet bağlantını kontrol edip yeniden dene.")
        }
        NSApp.activate(ignoringOtherApps: true)
        if uyari.runModal() == .alertFirstButtonReturn, yeniSurum != nil { sayfayiAc() }
    }
}
