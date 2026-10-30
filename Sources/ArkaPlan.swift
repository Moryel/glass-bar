import AppKit
import SwiftUI

// Camın arkası (menüde "Arka plan"): kapalı, uygulamanın renginde ışık, hazır renk stilleri, Mac'in duvar kağıdı
// ya da seçilen bir görsel. Görsel ve duvar kağıdı çubuğun ölçüsüne kırpılıp kısılır ki tuşlar okunsun.
enum ArkaPlan: String, CaseIterable {
    case kapali, uygulama, aurora, gunBatimi, okyanus, siri, duvarKagidi, gorsel

    var ad: String { L(adTr) }

    private var adTr: String {
        switch self {
        case .kapali: "Kapalı"
        case .uygulama: "Uygulamanın rengi"
        case .aurora: "Aurora"
        case .gunBatimi: "Gün batımı"
        case .okyanus: "Okyanus"
        case .siri: "Siri renkleri"
        case .duvarKagidi: "Duvar kağıdı"
        case .gorsel: "Görsel seç…"
        }
    }

    /// Işık stillerinin üç lekesinin renkleri; uygulama renginde nil (öndeki uygulamanın rengi kullanılır).
    var renkler: [NSColor]? {
        switch self {
        case .aurora: [NSColor(srgbRed: 0.2, green: 0.95, blue: 0.6, alpha: 1), NSColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1),
                       NSColor(srgbRed: 0.7, green: 0.35, blue: 1, alpha: 1)]
        case .gunBatimi: [NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 1), NSColor(srgbRed: 1, green: 0.3, blue: 0.45, alpha: 1),
                          NSColor(srgbRed: 0.6, green: 0.25, blue: 0.85, alpha: 1)]
        case .okyanus: [NSColor(srgbRed: 0.1, green: 0.45, blue: 1, alpha: 1), NSColor(srgbRed: 0.1, green: 0.8, blue: 0.85, alpha: 1),
                        NSColor(srgbRed: 0.2, green: 0.3, blue: 0.9, alpha: 1)]
        case .siri: SiriRenk.hepsi.dropFirst().map { NSColor($0) }
        default: nil
        }
    }

    var resimli: Bool { self == .duvarKagidi || self == .gorsel }

    /// Kaynak görseli çubuk boyutunda (2×), ortasından yatay bir şerit olarak hazırlar. Arka kuyrukta çağrılır.
    static func serit(_ url: URL, genislik: CGFloat) -> NSImage? {
        guard let kaynak = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(kaynak, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary)
        else { return nil }
        let w = Int(genislik * 2), h = Int(Olcu.yukseklik * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // en boyu koruyarak genişliğe sığdır, dikeyde ortadaki şerit kalsın
        let olcek = CGFloat(w) / CGFloat(cg.width)
        let ch = CGFloat(cg.height) * olcek
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: (CGFloat(h) - ch) / 2, width: CGFloat(w), height: ch))
        guard let sonuc = ctx.makeImage() else { return nil }
        return NSImage(cgImage: sonuc, size: NSSize(width: genislik, height: Olcu.yukseklik))
    }

    /// Ana ekranın duvar kağıdı (dinamik/hareketli duvar kağıdında dosya olmayabilir).
    static var duvarKagidiAdresi: URL? {
        guard let ekran = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: ekran)
    }
}
