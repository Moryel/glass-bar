import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio

// Touch Bar tuşlarının gerçek işleri: tuş/medya olayları, parlaklık, klavye ışığı, ses, uygulama açma.
enum Sistem {
    // NX_KEYTYPE_* (IOKit/hidsystem/ev_keymap.h)
    enum Ozel: Int {
        case sesArti = 0, sesEksi = 1, parlaklikArti = 2, parlaklikEksi = 3, sessiz = 7
        case oynat = 16, sonraki = 17, onceki = 18, klavyeArti = 21, klavyeEksi = 22
    }

    /// Medya/özel tuş; sistem kendi göstergesini (HUD) çıkarır. Erişilebilirlik izni ister.
    static func ozelTus(_ t: Ozel) {
        for basili in [true, false] {
            let durum = basili ? 0xA : 0xB
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(durum << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (t.rawValue << 16) | (durum << 8), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Klavye tuşu. `karakter` verilirse olay o karakteri taşır (Türkçe Q düzeninde ⌘[ gibi kısayollar için).
    static func tus(_ kod: CGKeyCode, _ bayrak: CGEventFlags = [], karakter: String? = nil) {
        let kaynak = CGEventSource(stateID: .hidSystemState)
        for basili in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: kaynak, virtualKey: kod, keyDown: basili) else { continue }
            ev.flags = bayrak
            if let karakter {
                let u = Array(karakter.utf16)
                ev.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            }
            ev.post(tap: .cghidEventTap)
        }
    }

    static var erisimVar: Bool { AXIsProcessTrusted() }

    /// ~/Library/Logs/TouchBar2.log dosyasına bir satır ekler (tanı için).
    static func gunluk(_ satir: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TouchBar2.log")
        guard let veri = "\(Date()) \(satir)\n".data(using: .utf8), let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        h.write(veri)
        try? h.close()
    }

    /// Uygulamanın menülerinde ⌘karakter (shift ise ⇧⌘) kısayoluna bağlı etkin öğeye basar. Bulursa true.
    /// Arka kuyrukta çağrılır; Erişilebilirlik ister.
    static func menuOgesi(_ pid: pid_t, _ karakter: String, shift: Bool) -> Bool {
        let uyg = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(uyg, 0.5)
        guard let cubuk = deger(uyg, kAXMenuBarAttribute) else { return false }
        let hedef = karakter.uppercased()
        // AXMenuItemCmdModifiers: 0 = yalnız ⌘, 1 = ⇧⌘
        let bayrak = shift ? 1 : 0
        func ara(_ o: AXUIElement, _ derinlik: Int) -> Bool {
            guard derinlik < 5, let cocuklar = deger(o, kAXChildrenAttribute) as? [AXUIElement] else { return false }
            for c in cocuklar {
                if let k = deger(c, kAXMenuItemCmdCharAttribute) as? String, k.uppercased() == hedef,
                   (deger(c, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0) == bayrak,
                   deger(c, kAXEnabledAttribute) as? Bool ?? true {
                    return AXUIElementPerformAction(c, kAXPressAction as CFString) == .success
                }
                if ara(c, derinlik + 1) { return true }
            }
            return false
        }
        return ara(cubuk as! AXUIElement, 0)
    }

    private static func deger(_ o: AXUIElement, _ ad: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, ad as CFString, &v) == .success ? v : nil
    }

    static func erisimIste() {
        let anahtar = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([anahtar: true] as CFDictionary)
    }

    static func ac(_ yol: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: yol), configuration: .init())
    }

    static func siri() {
        for yol in ["/System/Applications/Siri.app", "/System/Library/CoreServices/Siri.app"]
        where FileManager.default.fileExists(atPath: yol) { ac(yol); return }
    }

    /// macOS 26'dan beri Launchpad yok; aynı tuş "Uygulamalar"ı açar.
    static func launchpad() {
        ac(FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
           ? "/System/Applications/Apps.app" : "/System/Applications/Launchpad.app")
    }

    static func acPaket(_ paket: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: paket) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func missionControl() { ac("/System/Applications/Mission Control.app") }

    /// AppleScript ve Erişilebilirlik okumaları için: ana iş parçacığı (çubuğun çizimi) hiç beklemez.
    static let arka = DispatchQueue(label: "TouchBar2.arka", qos: .userInitiated)

    /// Komut betiğini arka planda çalıştırır.
    static func betikArka(_ kaynak: String) { arka.async { betik(kaynak) } }

    @discardableResult
    static func betik(_ kaynak: String) -> NSAppleEventDescriptor? {
        var hata: NSDictionary?
        return NSAppleScript(source: kaynak)?.executeAndReturnError(&hata)
    }
}

// Hangi Touch Bar: 2019 sonundan sonraki MacBook Pro'larda esc fiziksel bir tuş ve çubuk daha kısa
// (2008 px = 1004 pt); önceki modellerde esc çubuğun üstünde ve çubuk 2170 px = 1085 pt.
enum Donanim {
    static let model: String = {
        var boyut = 0
        sysctlbyname("hw.model", nil, &boyut, nil, 0)
        var b = [CChar](repeating: 0, count: max(1, boyut))
        sysctlbyname("hw.model", &b, &boyut, nil, 0)
        return String(cString: b)
    }()

    static let fizikselEsc = ["MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
                              "MacBookPro17,1", "Mac14,7"].contains(model)
    static let genislik: CGFloat = fizikselEsc ? 1004 : 1085
}

// Yerleşik ekran parlaklığı (DisplayServices, özel çatı).
enum Ekran {
    private static let kutup = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private typealias Oku = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Yaz = @convention(c) (UInt32, Float) -> Int32

    private static var ekran: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var parlaklik: Float {
        get {
            guard let f = dlsym(kutup, "DisplayServicesGetBrightness") else { return 0.5 }
            var v: Float = 0.5
            _ = unsafeBitCast(f, to: Oku.self)(ekran, &v)
            return v
        }
        set {
            guard let f = dlsym(kutup, "DisplayServicesSetBrightness") else { return }
            _ = unsafeBitCast(f, to: Yaz.self)(ekran, min(1, max(0, newValue)))
        }
    }
}

// Klavye arka ışığı (CoreBrightness → KeyboardBrightnessClient, özel sınıf).
enum KlavyeIsigi {
    private static let istemci: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let sinif = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return sinif.init()
    }()

    private static var kimlik: UInt64 {
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let i = istemci, i.responds(to: sel),
              let dizi = i.perform(sel)?.takeUnretainedValue() as? [NSNumber], let ilk = dizi.first
        else { return 1 }
        return ilk.uint64Value
    }

    static var deger: Float {
        get {
            let sel = NSSelectorFromString("brightnessForKeyboard:")
            guard let i = istemci, i.responds(to: sel) else { return 0.5 }
            typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Float
            return unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, kimlik)
        }
        set {
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            guard let i = istemci, i.responds(to: sel) else { return }
            typealias F = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
            _ = unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, min(1, max(0, newValue)), kimlik)
        }
    }
}

// Varsayılan çıkış aygıtının sesi (CoreAudio).
enum Ses {
    private static var cihaz: AudioDeviceID {
        var id = AudioDeviceID(0)
        var boyut = UInt32(MemoryLayout<AudioDeviceID>.size)
        var adres = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adres, 0, nil, &boyut, &id)
        return id
    }

    private static func adres(_ secici: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: secici, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var seviye: Float {
        get {
            var a = adres(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var v: Float32 = 0
            var boyut = UInt32(MemoryLayout<Float32>.size)
            AudioHardwareServiceGetPropertyData(cihaz, &a, 0, nil, &boyut, &v)
            return v
        }
        set {
            var a = adres(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var v = Float32(min(1, max(0, newValue)))
            AudioHardwareServiceSetPropertyData(cihaz, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if v > 0, sessiz { sessiz = false }
        }
    }

    static var sessiz: Bool {
        get {
            var a = adres(kAudioDevicePropertyMute)
            var v: UInt32 = 0
            var boyut = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(cihaz, &a, 0, nil, &boyut, &v)
            return v != 0
        }
        set {
            var a = adres(kAudioDevicePropertyMute)
            var v: UInt32 = newValue ? 1 : 0
            AudioObjectSetPropertyData(cihaz, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        }
    }
}

enum Finder {
    /// Finder etiket sırası: 0 yok, 1 turuncu, 2 kırmızı, 3 sarı, 4 mavi, 5 mor, 6 yeşil, 7 gri.
    static func etiket(_ sira: Int) {
        Sistem.betikArka("""
        tell application "Finder"
            repeat with f in (get selection)
                set label index of f to \(sira)
            end repeat
        end tell
        """)
    }
}

extension NSImage {
    /// Uygulama simgesinin baskın rengi: doygun piksellerin ortalaması.
    var baskinRenk: NSColor {
        let n = 24
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))),
              let veri = ctx.data?.assumingMemoryBound(to: UInt8.self)
        else { return .systemBlue }
        var r = 0.0, g = 0.0, b = 0.0, toplam = 0.0
        for i in 0..<(n * n) {
            let a = Double(veri[i * 4 + 3]) / 255
            guard a > 0.6 else { continue }
            let c = NSColor(srgbRed: Double(veri[i * 4]) / 255 / a, green: Double(veri[i * 4 + 1]) / 255 / a,
                            blue: Double(veri[i * 4 + 2]) / 255 / a, alpha: 1)
            let w = c.saturationComponent * c.brightnessComponent
            guard w > 0.12 else { continue }
            r += c.redComponent * w; g += c.greenComponent * w; b += c.blueComponent * w; toplam += w
        }
        guard toplam > 0 else { return .systemBlue }
        let c = NSColor(srgbRed: r / toplam, green: g / toplam, blue: b / toplam, alpha: 1)
        return NSColor(hue: c.hueComponent, saturation: max(0.55, c.saturationComponent),
                       brightness: max(0.8, c.brightnessComponent), alpha: 1)
    }
}
