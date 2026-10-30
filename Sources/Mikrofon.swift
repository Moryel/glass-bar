import AVFoundation
import Combine

// Siri dinlerken mikrofonun ses seviyesi (yalnız Siri hapı açıkken dinlenir, ses kaydedilmez ve hiçbir yere gönderilmez).
// İlk kullanımda macOS mikrofon izni sorar.
final class Mikrofon: ObservableObject {
    static let ortak = Mikrofon()
    /// 0…1, yumuşatılmış
    @Published var seviye: Double = 0
    /// izin yoksa ya da çalışmıyorsa false: dalga eski kendi kendine oynayan haline döner
    @Published var calisiyor = false
    private var motor: AVAudioEngine?
    private var ham: Double = 0
    /// ortamın gürültü seviyesi (dB): sessizliğe hızla iner, sese çok yavaş çıkar; konuşma bunun üstünden ölçülür
    private var zemin: Float = -50

    func baslat() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: ac()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { izin in if izin { DispatchQueue.main.async { self.ac() } } }
        default: Sistem.gunluk("mikrofon: izin yok")
        }
    }

    private func ac() {
        guard motor == nil else { return }
        let m = AVAudioEngine()
        let giris = m.inputNode
        let bicim = giris.outputFormat(forBus: 0)
        guard bicim.sampleRate > 0 else { return }
        giris.installTap(onBus: 0, bufferSize: 1024, format: bicim) { [weak self] tampon, _ in
            guard let self, let kanal = tampon.floatChannelData?[0] else { return }
            let n = Int(tampon.frameLength)
            var toplam: Float = 0
            for i in 0..<n { toplam += kanal[i] * kanal[i] }
            let rms = sqrt(toplam / Float(max(1, n)))
            let db = 20 * log10(max(rms, 1e-6))
            DispatchQueue.main.async {
                // arka plan gürültüsü: zemin sessiz anlara hızla iner, sürekli sese yavaşça uyar
                self.zemin += (db - self.zemin) * (db < self.zemin ? 0.3 : 0.004)
                // zeminin 8 dB üstü (konuşma başlangıcı) … 32 dB üstü → 0…1; altı tamamen sıfır
                let v = Double(min(1, max(0, (db - self.zemin - 8) / 24)))
                // yükselirken hızlı, düşerken yavaş (iOS'teki dalga gibi)
                self.ham = v > self.ham ? self.ham + (v - self.ham) * 0.6 : self.ham + (v - self.ham) * 0.15
                self.seviye = self.ham
            }
        }
        do {
            try m.start()
            motor = m
            calisiyor = true
        } catch {
            giris.removeTap(onBus: 0)
            Sistem.gunluk("mikrofon: başlatılamadı (\(error.localizedDescription))")
        }
    }

    func durdur() {
        motor?.inputNode.removeTap(onBus: 0)
        motor?.stop()
        motor = nil
        calisiyor = false
        ham = 0
        seviye = 0
        zemin = -50
    }
}
