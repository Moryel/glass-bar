import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Spotify'ın çıkardığı sesi Core Audio ses yakalama (process tap, macOS 14.2+) ile dinler ve frekans bantlarına ayırır;
/// ses dalgası bu bantlarla oynar. Ses kaydedilmez, yalnız seviyesi ölçülür. İlk kullanımda macOS
/// "sistem sesini kaydetme" izni sorar; izin yoksa ya da yakalama kurulamazsa `calisiyor` false kalır.
final class SesYakalayici: ObservableObject {
    static let ortak = SesYakalayici()
    static let bantSayisi = 14

    /// Her yeni ölçümde ana iş parçacığında çağrılır. SwiftUI yayını yerine doğrudan katmanlara çizilir:
    /// saniyede ~23 güncelleme SwiftUI'den geçince işlemci yükü ~%10'a çıkıyordu.
    var dinleyici: (([Float]) -> Void)?
    @Published private(set) var calisiyor = false

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agrega = AudioObjectID(kAudioObjectUnknown)
    private var islem: AudioDeviceIOProcID?
    private let kuyruk = DispatchQueue(label: "GlassBar.ses", qos: .userInteractive)
    private var sonDeneme = Date.distantPast

    /// Her saniye çağrılır: açık olması gerekiyorsa kurar (kurulamadıysa 5 sn'de bir yeniden dener), değilse söker.
    func ayarla(acik: Bool) {
        if acik {
            guard tap == kAudioObjectUnknown, Date().timeIntervalSince(sonDeneme) > 5 else { return }
            sonDeneme = Date()
            if #available(macOS 14.2, *) { kur() }
        } else if tap != kAudioObjectUnknown {
            sok()
        }
    }

    @available(macOS 14.2, *)
    private func kur() {
        let surecler = Self.spotifySurecleri()
        guard !surecler.isEmpty else { Sistem.gunluk("ses yakalama: Spotify ses süreci yok"); return }
        let tanim = CATapDescription(stereoMixdownOfProcesses: surecler)
        tanim.name = "GlassBar"
        tanim.isPrivate = true
        tanim.muteBehavior = .unmuted
        let tapHata = AudioHardwareCreateProcessTap(tanim, &tap)
        guard tapHata == noErr else { Sistem.gunluk("ses yakalama: tap kurulamadı (\(tapHata))"); tap = kAudioObjectUnknown; return }

        var bicim = AudioStreamBasicDescription()
        var boyut = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var adres = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tap, &adres, 0, nil, &boyut, &bicim)
        let kanal = max(1, Int(bicim.mChannelsPerFrame)), hiz = bicim.mSampleRate > 0 ? Float(bicim.mSampleRate) : 48000

        var ayar: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GlassBar",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tanim.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        if let cikis = Self.cikisAygitiUID() {
            ayar[kAudioAggregateDeviceMainSubDeviceKey] = cikis
            ayar[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: cikis]]
        }
        let agregaHata = AudioHardwareCreateAggregateDevice(ayar as CFDictionary, &agrega)
        guard agregaHata == noErr else { Sistem.gunluk("ses yakalama: aygıt kurulamadı (\(agregaHata))"); sok(); return }

        let cozumleyici = Cozumleyici(hiz: hiz, kanal: kanal)
        let durum = AudioDeviceCreateIOProcIDWithBlock(&islem, agrega, kuyruk) { [weak self] _, giris, _, _, _ in
            let liste = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: giris))
            guard let tampon = liste.first, let veri = tampon.mData else { return }
            let kare = Int(tampon.mDataByteSize) / MemoryLayout<Float>.size / kanal
            if let yeni = cozumleyici.ekle(veri.assumingMemoryBound(to: Float.self), kare: kare) {
                DispatchQueue.main.async { self?.dinleyici?(yeni) }
            }
        }
        let baslat = durum == noErr ? AudioDeviceStart(agrega, islem) : durum
        guard baslat == noErr else { Sistem.gunluk("ses yakalama: başlatılamadı (\(baslat))"); sok(); return }
        calisiyor = true
        Sistem.gunluk("ses yakalama: açık (\(surecler.count) Spotify süreci)")
    }

    private func sok() {
        if let islem, agrega != kAudioObjectUnknown {
            AudioDeviceStop(agrega, islem)
            AudioDeviceDestroyIOProcID(agrega, islem)
        }
        islem = nil
        if agrega != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agrega) }
        if tap != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
        agrega = kAudioObjectUnknown
        tap = kAudioObjectUnknown
        calisiyor = false
        dinleyici?([Float](repeating: 0, count: Self.bantSayisi))
    }

    // MARK: Core Audio nesneleri

    private static func adres(_ secici: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: secici, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Ses çıkaran Spotify süreçlerinin Core Audio nesneleri (ana uygulama ve yardımcıları).
    private static func spotifySurecleri() -> [AudioObjectID] {
        var a = adres(kAudioHardwarePropertyProcessObjectList)
        var boyut: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &boyut) == noErr else { return [] }
        var nesneler = [AudioObjectID](repeating: 0, count: Int(boyut) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &boyut, &nesneler) == noErr else { return [] }
        return nesneler.filter { nesne in
            var b = adres(kAudioProcessPropertyBundleID)
            var kimlik: CFString? = nil
            var k = UInt32(MemoryLayout<CFString?>.size)
            guard AudioObjectGetPropertyData(nesne, &b, 0, nil, &k, &kimlik) == noErr, let kimlik else { return false }
            return (kimlik as String).hasPrefix("com.spotify.")
        }
    }

    private static func cikisAygitiUID() -> String? {
        var a = adres(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var aygit = AudioObjectID(kAudioObjectUnknown)
        var boyut = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &boyut, &aygit) == noErr else { return nil }
        var u = adres(kAudioDevicePropertyDeviceUID)
        var uid: CFString? = nil
        var k = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(aygit, &u, 0, nil, &k, &uid) == noErr else { return nil }
        return uid as String?
    }
}

/// 1024 örneklik pencerelerde FFT; 50 Hz–14 kHz arası logaritmik bantlar, her bant 0…1.
/// Her bant kendi yakın geçmişteki tepesine göre ölçülür (24 dB aralık): bas hep baskın kalmaz, vuruşlar ve tizler ayrı oynar.
/// Ses açıklığından bağımsızdır; sessizlikte (-75 dB altı) çubuklar iner. Sonuç her iki pencerede bir verilir (~23/sn).
private final class Cozumleyici {
    private let n = 1024, log2n: vDSP_Length = 10
    private let kanal: Int
    private let kurulum: FFTSetup
    private let pencere: [Float]
    private var ornekler: [Float]
    private var dolu = 0
    private var tepeler = [Float](repeating: -60, count: SesYakalayici.bantSayisi)
    private var sayac = 0
    private var son = [Float](repeating: 0, count: SesYakalayici.bantSayisi)
    private let kenarlar: [Int]

    init(hiz: Float, kanal: Int) {
        self.kanal = kanal
        kurulum = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        pencere = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        ornekler = [Float](repeating: 0, count: n)
        let adet = SesYakalayici.bantSayisi, yarim = 512, cozunurluk = hiz / 1024
        kenarlar = (0...adet).map { i in
            let f = 50 * pow(14000 / 50, Float(i) / Float(adet))
            return min(yarim - 1, max(1, Int(f / cozunurluk)))
        }
    }

    deinit { vDSP_destroy_fftsetup(kurulum) }

    func ekle(_ p: UnsafePointer<Float>, kare: Int) -> [Float]? {
        var sonuc: [Float]?
        for i in 0..<kare {
            var t: Float = 0
            for k in 0..<kanal { t += p[i * kanal + k] }
            ornekler[dolu] = t / Float(kanal)
            dolu += 1
            if dolu == n {
                dolu = 0
                let yeni = cozumle()
                sayac += 1
                if sayac % 2 == 0 { sonuc = yeni }
            }
        }
        return sonuc
    }

    private func cozumle() -> [Float] {
        let yarim = n / 2
        let x = vDSP.multiply(ornekler, pencere)
        var gercek = [Float](repeating: 0, count: yarim), sanal = [Float](repeating: 0, count: yarim)
        var genlik = [Float](repeating: 0, count: yarim)
        gercek.withUnsafeMutableBufferPointer { g in
            sanal.withUnsafeMutableBufferPointer { s in
                var z = DSPSplitComplex(realp: g.baseAddress!, imagp: s.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: yarim) { vDSP_ctoz($0, 2, &z, 1, vDSP_Length(yarim)) }
                }
                vDSP_fft_zrip(kurulum, &z, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&z, 1, &genlik, 1, vDSP_Length(yarim))
            }
        }
        let db: [Float] = (0..<SesYakalayici.bantSayisi).map { i in
            let a = kenarlar[i], b = max(a + 1, kenarlar[i + 1])
            let ort = genlik[a..<b].reduce(0, +) / Float(b - a)
            return 20 * log10(ort + 1e-7)
        }
        for i in son.indices {
            tepeler[i] = max(db[i], tepeler[i] - 0.25)
            let hedef = db[i] < -75 ? 0 : min(1, max(0, (db[i] - (tepeler[i] - 24)) / 24))
            // yükselirken hızlı, düşerken yavaş (orijinal ekolayzırlar gibi)
            son[i] = hedef > son[i] ? son[i] + (hedef - son[i]) * 0.6 : son[i] * 0.8 + hedef * 0.2
        }
        return son
    }
}
