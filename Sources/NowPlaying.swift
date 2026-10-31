import AppKit
import AVFoundation

// Now Playing: reads and controls what plays in Music, Spotify and QuickTime through AppleScript.
// (System-wide "now playing" info lives in MediaRemote, closed to third-party apps since macOS 15.4.)
struct NowPlaying: Equatable {
    var source: String
    var name: String
    var artist: String
    var position: Double
    var duration: Double
    var isPlaying: Bool
    var filePath: String?
    /// Album art URL in Spotify.
    var artworkURL: String? = nil

    static let music = "com.apple.Music", spotify = "com.spotify.client", quickTime = "com.apple.QuickTimePlayerX"
    static let sources = [music, spotify, quickTime]

    var video: Bool { source == NowPlaying.quickTime }

    /// Among running sources: the front app's first, then one that's playing, then a paused one.
    /// Called on the work queue; `runningBundleIDs` is collected on the main thread.
    static func read(frontBundleID: String, runningBundleIDs: Set<String>) -> NowPlaying? {
        let candidates = sources.filter(runningBundleIDs.contains).compactMap(read(source:))
        return candidates.first { $0.source == frontBundleID } ?? candidates.first(where: \.isPlaying) ?? candidates.first
    }

    private static func read(source: String) -> NowPlaying? {
        let runScript: String
        switch source {
        case music, spotify:
            let appName = source == music ? "Music" : "Spotify"
            let duration = source == music ? "duration of current track" : "(duration of current track) / 1000"
            runScript = """
            tell application "\(appName)"
                if player state is stopped then return {}
                return {name of current track, artist of current track, player position, \(duration), (player state is playing), \(source == spotify ? "artwork url of current track" : "\"\"")}
            end tell
            """
        default:
            runScript = """
            tell application "QuickTime Player"
                if (count documents) = 0 then return {}
                set d to document 1
                set yol to ""
                try
                    set yol to POSIX path of (file of d as alias)
                end try
                return {name of d, "", current time of d, duration of d, playing of d, yol}
            end tell
            """
        }
        guard let d = SystemControl.runScript(runScript), d.numberOfItems == 6 else { return nil }
        let path = d.atIndex(6)?.stringValue ?? ""
        return NowPlaying(source: source, name: d.atIndex(1)?.stringValue ?? "", artist: d.atIndex(2)?.stringValue ?? "",
                     position: d.atIndex(3)?.doubleValue ?? 0, duration: max(1, d.atIndex(4)?.doubleValue ?? 1),
                     isPlaying: d.atIndex(5)?.booleanValue ?? false,
                     filePath: path.isEmpty || source == spotify ? nil : path, artworkURL: source == spotify && !path.isEmpty ? path : nil)
    }

    private var appName: String { source == NowPlaying.music ? "Music" : source == NowPlaying.spotify ? "Spotify" : "QuickTime Player" }

    func playPause() {
        SystemControl.runScriptInBackground(video
            ? "tell application \"QuickTime Player\" to tell document 1 to if playing then pause else play"
            : "tell application \"\(appName)\" to playpause")
    }

    /// 15 s forward/back for video, next/previous track for music.
    func next() {
        SystemControl.runScriptInBackground(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(min(duration, position + 15))"
                           : "tell application \"\(appName)\" to next track")
    }

    func previous() {
        SystemControl.runScriptInBackground(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(max(0, position - 15))"
                           : "tell application \"\(appName)\" to previous track")
    }

    func seek(_ seconds: Double) {
        SystemControl.runScriptInBackground(video ? "tell application \"QuickTime Player\" to set current time of document 1 to \(seconds)"
                           : "tell application \"\(appName)\" to set player position to \(seconds)")
    }

    func love() {
        guard source == NowPlaying.music else { return }
        SystemControl.runScriptInBackground("""
        tell application "Music"
            try
                set favorited of current track to true
            on error
                set loved of current track to true
            end try
        end tell
        """)
    }
}

/// Video thumbnails (AVKit's filmstrip in the original).
final class Filmstrip: ObservableObject {
    static let shared = Filmstrip()
    /// thumbnails of the video open in Photos (separate so they don't mix with QuickTime's)
    static let photos = Filmstrip()
    /// thumbnails of the video playing in Safari (YouTube)
    static let safari = Filmstrip()
    static let frameCount = 16
    @Published var images: [NSImage] = []
    private var path: String?

    /// Ready-made thumbnails (YouTube storyboard); not reloaded if `key` is unchanged.
    func setImages(_ r: [NSImage], key: String) {
        path = key
        images = r
    }

    func load(_ path: String?) {
        guard path != self.path else { return }
        self.path = path
        images = []
        guard let path else { return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 140, height: 80)
        Task {
            guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return }
            var r: [NSImage] = []
            for i in 0..<Filmstrip.frameCount {
                let t = CMTime(seconds: duration * (Double(i) + 0.5) / Double(Filmstrip.frameCount), preferredTimescale: 600)
                if let (cg, _) = try? await generator.image(at: t) { r.append(NSImage(cgImage: cg, size: .zero)) }
            }
            let last = r
            await MainActor.run { if self.path == path { self.images = last } }
        }
    }
}
