import AppKit
import SwiftUI

// MARK: Spotify player settings (the customizations from Spotiw)

protocol MenuOption: RawRepresentable, CaseIterable where RawValue == String {
    var name: String { get }
}

enum SpotifyPlacement: String, MenuOption {
    case spotifyOnly = "spotify", desktop = "masaustu", everywhere = "her"
    var name: String {
        switch self {
        case .spotifyOnly: L("Only when Spotify is in front")
        case .desktop: L("On the desktop too")
        case .everywhere: L("In every app")
        }
    }
}

enum WaveStyle: String, MenuOption {
    case bars = "cubuk", wave = "dalga", dots = "nokta"
    var name: String {
        switch self {
        case .bars: L("Bars")
        case .wave: L("Wave")
        case .dots: L("Dots")
        }
    }
}

enum WaveColor: String, MenuOption {
    case artwork = "kapak", green = "yesil", white = "beyaz", blue = "mavi", purple = "mor", orange = "turuncu"
    var name: String {
        switch self {
        case .artwork: L("Album colors")
        case .green: L("Spotify green")
        case .white: L("White")
        case .blue: L("Blue")
        case .purple: L("Purple")
        case .orange: L("Orange")
        }
    }
    var color: Color? {
        switch self {
        case .artwork: nil
        case .green: Color(hex: 0x1DB954)
        case .white: .white
        case .blue: Color(hex: 0x3D8BFF)
        case .purple: Color(hex: 0x9B5CFF)
        case .orange: Color(hex: 0xFF6A3D)
        }
    }
}

enum WaveWidth: String, MenuOption {
    case narrow = "dar", medium = "orta", wide = "genis", extraWide = "cokGenis"
    var name: String {
        switch self {
        case .narrow: L("Narrow")
        case .medium: L("Medium")
        case .wide: L("Wide")
        case .extraWide: L("Extra wide")
        }
    }
    var points: CGFloat {
        switch self {
        case .narrow: 40
        case .medium: 62
        case .wide: 110
        case .extraWide: 180
        }
    }
}

/// How easily the sound bar reacts: the scale range (dB); a narrow range amplifies small changes.
enum Sensitivity: String, MenuOption {
    case low = "dusuk", normal, high = "yuksek"
    var name: String {
        switch self {
        case .low: L("Low")
        case .normal: L("Normal")
        case .high: L("High")
        }
    }
    var dynamicRange: Float {
        switch self {
        case .low: 32
        case .normal: 24
        case .high: 16
        }
    }
}

/// How the bars fall: how much of the previous level remains at each measurement.
enum Smoothness: String, MenuOption {
    case low = "az", normal, high = "cok"
    var name: String {
        switch self {
        case .low: L("smoothness.low")
        case .normal: L("Normal")
        case .high: L("smoothness.high")
        }
    }
    var decay: Float {
        switch self {
        case .low: 0.6
        case .normal: 0.8
        case .high: 0.9
        }
    }
}

/// Album art of the track playing in Spotify and the colors taken from it (the sound bar is painted with them).
/// The art is downloaded once per track from the URL Spotify provides.
final class Artwork: ObservableObject {
    static let shared = Artwork()
    @Published private(set) var image: NSImage?
    @Published private(set) var colors: [Color] = [Color(hex: 0x1DB954)]
    private var address: String?

    func load(_ newURL: String?) {
        guard newURL != address else { return }
        address = newURL
        guard let newURL, let url = URL(string: newURL) else { image = nil; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let colors = Artwork.palette(data)
            DispatchQueue.main.async {
                guard let self, self.address == newURL else { return }
                self.image = image
                if !colors.isEmpty { self.colors = colors }
            }
        }.resume()
    }

    /// The art's most frequent colors; dark colors are lightened because the Touch Bar is black.
    private static func palette(_ data: Data, count: Int = 5) -> [Color] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let k = 24
        guard let c = CGContext(data: nil, width: k, height: k, bitsPerComponent: 8, bytesPerRow: k * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(c.draw(img, in: CGRect(x: 0, y: 0, width: k, height: k))),
              let buffer = c.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        var buckets: [Int: Int] = [:]
        for i in 0..<(k * k) {
            let r = Int(buffer[i * 4]), g = Int(buffer[i * 4 + 1]), b = Int(buffer[i * 4 + 2])
            buckets[(r / 64) << 4 | (g / 64) << 2 | (b / 64), default: 0] += 1
        }
        return buckets.sorted { $0.value > $1.value }.prefix(count).map { bucket, _ in
            let color = NSColor(deviceRed: CGFloat((bucket >> 4) & 3) * 64 / 255 + 0.125,
                               green: CGFloat((bucket >> 2) & 3) * 64 / 255 + 0.125,
                               blue: CGFloat(bucket & 3) * 64 / 255 + 0.125, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, p: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &p, alpha: &a)
            return Color(nsColor: p < 0.6 ? NSColor(deviceHue: h, saturation: min(s, 0.8), brightness: 0.6 + p * 0.3, alpha: 1) : color)
        }
    }
}

/// App area while Spotify plays (Spotiw's layout): album art, track name and artist, previous/play/next,
/// a scrubber with times, and a sound bar in the album colors.
struct SpotifyPlayer: View {
    @ObservedObject var d: AppState
    let c: NowPlaying
    @ObservedObject private var artwork = Artwork.shared

    var body: some View {
        HStack(spacing: 7) {
            if d.showsArtwork {
            Group {
                if let image = artwork.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.1))
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(c.name).font(.system(size: 11.5, weight: .semibold))
                Text(c.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .opacity(c.isPlaying ? 1 : 0.6)
            .frame(width: 118, alignment: .leading)
        }
        .padding(.leading, 4)
        .contentShape(Rectangle())
        .onTapGesture { SystemControl.openApp(c.source) }

        ButtonGroup(buttons: [.init(symbol: "backward.fill") { d.nowPlayingCommand { $0.previous() } },
                      .init(symbol: c.isPlaying ? "pause.fill" : "play.fill") { d.nowPlayingCommand { $0.playPause() } },
                      .init(symbol: "forward.fill") { d.nowPlayingCommand { $0.next() } }],
             buttonWidth: Metrics.narrowWidth + 2)

        HStack(spacing: 6) {
            // times have fixed widths because fixedSize truncates text on the Touch Bar
            Text(TimeFormat.typeText(Double(d.nowPlayingProgress) * c.duration)).frame(width: 34, alignment: .trailing)
            GlassSlider(value: $d.nowPlayingProgress, isThin: true, onValueChange: { d.scrubNowPlaying($0) }).frame(height: 10)
            Text("-" + TimeFormat.typeText(c.duration * (1 - Double(d.nowPlayingProgress)))).frame(width: 38, alignment: .leading)
        }
        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)

        SoundBars(isPlaying: c.isPlaying, colors: d.waveColor.color.map { [$0] } ?? artwork.colors, style: d.waveStyle)
            .frame(width: d.waveWidth.points, height: 20).padding(.trailing, 4)
    }
}

/// Bars in the album colors. With audio capture on, they follow the frequency bands of Spotify's audio (bass → treble, left to right);
/// without permission they animate a stand-in wave while playing. They rest when paused.
struct SoundBars: View {
    let isPlaying: Bool
    let colors: [Color]
    var style: WaveStyle = .bars
    @ObservedObject private var audio = AudioCapture.shared
    private let count = AudioCapture.bandCount

    var body: some View {
        if !isPlaying {
            bars([Double](repeating: 0, count: count))
        } else if audio.isRunning {
            LiveSoundBars(colors: colors, style: style)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                bars((0..<count).map { i in
                    let x = Double(i)
                    return abs(sin(t * (3.1 + x * 0.37) + x * 1.7) * 0.6 + sin(t * (5.3 + x * 0.21) + x) * 0.4)
                })
            }
        }
    }

    /// A single Canvas instead of 14 separate views per frame: CPU use drops noticeably.
    private func bars(_ levels: [Double]) -> some View {
        let colors = colors, count = count
        return Canvas { ctx, size in
            let spacing: CGFloat = 1.5
            let w = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            for i in 0..<count {
                let h = 4 + (size.height - 4) * CGFloat(levels[i])
                let r = CGRect(x: CGFloat(i) * (w + spacing), y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(colors[i * colors.count / count]))
            }
        }
    }
}

/// A wave that moves with the real audio: each AudioCapture measurement is written straight into CALayers.
struct LiveSoundBars: NSViewRepresentable {
    let colors: [Color]
    let style: WaveStyle

    func makeNSView(context: Context) -> SoundBarsView {
        let v = SoundBarsView()
        AudioCapture.shared.onLevels = { [weak v] in v?.render($0) }
        return v
    }

    func updateNSView(_ v: SoundBarsView, context: Context) {
        v.style = style
        v.colors = colors.map { NSColor($0).cgColor }
    }
}

/// Three styles: bars (capsules growing from the middle), dots (stacked dots), wave (a filled curve through the bands).
final class SoundBarsView: NSView {
    private let count = AudioCapture.bandCount
    private let dotsPerBand = 5
    private var barLayers: [CALayer] = []
    private let gradient = CAGradientLayer()
    private let waveMask = CAShapeLayer()
    private var last: [Float]
    var style: WaveStyle = .bars { didSet { if style != oldValue { rebuildLayers() } } }
    var colors: [CGColor] = [] { didSet { applyColors() } }

    init() {
        last = [Float](repeating: 0, count: count)
        super.init(frame: .zero)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.mask = waveMask
        rebuildLayers()
    }

    required init?(coder: NSCoder) { nil }

    private func rebuildLayers() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        barLayers = []
        if style == .wave {
            layer?.addSublayer(gradient)
        } else {
            for _ in 0..<(style == .dots ? count * dotsPerBand : count) {
                let k = CALayer()
                layer?.addSublayer(k)
                barLayers.append(k)
            }
        }
        applyColors()
        render(last)
    }

    private func applyColors() {
        guard !colors.isEmpty else { return }
        let bandColor = { (i: Int) in self.colors[i * self.colors.count / self.count] }
        if style == .wave {
            gradient.colors = colors.count > 1 ? colors : [colors[0], colors[0]]
        } else {
            let groupSize = style == .dots ? dotsPerBand : 1
            for (j, k) in barLayers.enumerated() { k.backgroundColor = bandColor(j / groupSize) }
        }
    }

    override func layout() {
        super.layout()
        render(last)
    }

    func render(_ levels: [Float]) {
        last = levels
        let b = bounds, spacing: CGFloat = 1.5
        let w = (b.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch style {
        case .bars:
            for (i, k) in barLayers.enumerated() {
                let h = 4 + (b.height - 4) * CGFloat(levels[i])
                k.frame = CGRect(x: CGFloat(i) * (w + spacing), y: (b.height - h) / 2, width: w, height: h)
                k.cornerRadius = w / 2
            }
        case .dots:
            let d = min(w, (b.height - CGFloat(dotsPerBand - 1)) / CGFloat(dotsPerBand))
            for i in 0..<count {
                // dots light up from the middle outward; the middle one is always lit
                let litCount = 1 + Int((CGFloat(levels[i]) * CGFloat(dotsPerBand - 1)).rounded())
                for j in 0..<dotsPerBand {
                    let k = barLayers[i * dotsPerBand + j]
                    let index = abs(j - dotsPerBand / 2) * 2 + (j < dotsPerBand / 2 ? 1 : 0)
                    k.frame = CGRect(x: CGFloat(i) * (w + spacing) + (w - d) / 2,
                                     y: (b.height - d) / 2 + CGFloat(j - dotsPerBand / 2) * (d + 1), width: d, height: d)
                    k.cornerRadius = d / 2
                    k.opacity = index < litCount ? 1 : 0.15
                }
            }
        case .wave:
            gradient.frame = b
            let midY = b.height / 2
            let topPoints = (0..<count).map { i in
                CGPoint(x: CGFloat(i) * (w + spacing) + w / 2, y: midY + 1 + (midY - 1) * CGFloat(levels[i]))
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: midY))
            Self.smoothCurve(path, topPoints)
            path.addLine(to: CGPoint(x: b.width, y: midY))
            Self.smoothCurve(path, topPoints.reversed().map { CGPoint(x: $0.x, y: 2 * midY - $0.y) })
            path.closeSubpath()
            waveMask.path = path
        }
        CATransaction.commit()
    }

    /// Smooth curve through the points: to the midpoint of each pair, using the previous point as the control point.
    private static func smoothCurve(_ path: CGMutablePath, _ p: [CGPoint]) {
        guard let first = p.first, let last = p.last else { return }
        path.addLine(to: first)
        for i in 1..<p.count {
            path.addQuadCurve(to: CGPoint(x: (p[i - 1].x + p[i].x) / 2, y: (p[i - 1].y + p[i].y) / 2), control: p[i - 1])
        }
        path.addLine(to: last)
    }
}
