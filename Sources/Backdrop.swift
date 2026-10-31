import AppKit
import SwiftUI

// Behind the glass ("Background" in the menu): off, a glow in the app's color, preset color styles, the Mac's wallpaper
// or a chosen image. Image and wallpaper are cropped to the bar's size and dimmed so the buttons stay readable.
enum Backdrop: String, CaseIterable {
    case off = "kapali", app = "uygulama", aurora, sunset = "gunBatimi", ocean = "okyanus", siri, wallpaper = "duvarKagidi",
         customImage = "gorsel"

    var name: String { L(baseName) }

    private var baseName: String {
        switch self {
        case .off: "Off"
        case .app: "App Color"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .siri: "Siri Colors"
        case .wallpaper: "Wallpaper"
        case .customImage: "Choose Image…"
        }
    }

    /// Colors of the three blobs of the light styles; nil for the app color (the front app's color is used).
    var colors: [NSColor]? {
        switch self {
        case .aurora: [NSColor(srgbRed: 0.2, green: 0.95, blue: 0.6, alpha: 1), NSColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1),
                       NSColor(srgbRed: 0.7, green: 0.35, blue: 1, alpha: 1)]
        case .sunset: [NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 1), NSColor(srgbRed: 1, green: 0.3, blue: 0.45, alpha: 1),
                          NSColor(srgbRed: 0.6, green: 0.25, blue: 0.85, alpha: 1)]
        case .ocean: [NSColor(srgbRed: 0.1, green: 0.45, blue: 1, alpha: 1), NSColor(srgbRed: 0.1, green: 0.8, blue: 0.85, alpha: 1),
                        NSColor(srgbRed: 0.2, green: 0.3, blue: 0.9, alpha: 1)]
        case .siri: SiriColors.all.dropFirst().map { NSColor($0) }
        default: nil
        }
    }

    var isImage: Bool { self == .wallpaper || self == .customImage }

    /// Prepares the source image as a bar-sized (2×) horizontal strip from its middle. Called on the work queue.
    static func strip(_ url: URL, width: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary)
        else { return nil }
        let w = Int(width * 2), h = Int(Metrics.barHeight * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // fit the width keeping the aspect ratio, keep the middle strip vertically
        let scale = CGFloat(w) / CGFloat(cg.width)
        let scaledHeight = CGFloat(cg.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: (CGFloat(h) - scaledHeight) / 2, width: CGFloat(w), height: scaledHeight))
        guard let result = ctx.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: width, height: Metrics.barHeight))
    }

    /// The main screen's wallpaper (dynamic/animated wallpapers may have no file).
    static var wallpaperURL: URL? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }
}
