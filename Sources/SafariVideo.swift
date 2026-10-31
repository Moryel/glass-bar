import AppKit

// Video playing in Safari (YouTube etc.): the page's <video> element is read and controlled with AppleScript's
// "do JavaScript". This needs Develop → "Allow JavaScript from Apple Events" turned on in Safari.
// Thumbnails are cut from YouTube's own frame sheets (storyboard); on other sites the strip has no thumbnails.
struct SafariVideo: Equatable {
    var position: Float
    var duration: Double
    var isPaused: Bool
    /// page URL (thumbnails are fetched again when it changes)
    var address: String
    /// YouTube storyboard spec ("…|80#45#…") or empty
    var storyboardSpec: String

    var elapsed: Double { Double(position) * duration }
}

enum SafariPlayer {
    /// The largest video on the page with a known duration. On YouTube the storyboard comes from the player's current response.
    private static let readScript = """
    (function(){var v=[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.duration>0&&isFinite(x.duration)})\
    .sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight})[0];if(!v)return '';var sb='';\
    try{var p=document.querySelector('#movie_player');var r=(p&&p.getPlayerResponse&&p.getPlayerResponse())||window.ytInitialPlayerResponse;\
    sb=r.storyboards.playerStoryboardSpecRenderer.spec}catch(e){}\
    return JSON.stringify({t:v.currentTime,d:v.duration,p:v.paused,u:location.href,sb:sb})})()
    """

    private static func runJavaScript(_ js: String) -> NSAppleEventDescriptor? {
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: "tell application \"Safari\" to do JavaScript \"\(escaped)\" in current tab of front window")?
            .executeAndReturnError(&errorInfo)
        if let errorInfo, let n = errorInfo[NSAppleScript.errorNumber] as? Int, n != lastErrorNumber {
            lastErrorNumber = n
            SystemControl.log("safari video: JavaScript failed (\(n)) — Develop → Allow JavaScript from Apple Events")
        }
        return result
    }

    private static var lastErrorNumber = 0

    /// Called on the work queue. nil if there is no video.
    static func read() -> SafariVideo? {
        guard let s = runJavaScript(readScript)?.stringValue, let data = s.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["t"] as? Double, let d = j["d"] as? Double, d > 0 else { return nil }
        return SafariVideo(position: Float(t / d), duration: d, isPaused: j["p"] as? Bool ?? true,
                           address: j["u"] as? String ?? "", storyboardSpec: j["sb"] as? String ?? "")
    }

    private static let videoJS = "[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.duration>0})" +
        ".sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight})[0]"

    static func scrub(_ seconds: Double) { _ = runJavaScript("(function(){var v=\(videoJS);if(v)v.currentTime=\(seconds)})()") }
    static func playPause() { _ = runJavaScript("(function(){var v=\(videoJS);if(v){if(v.paused)v.play();else v.pause()}})()") }

    /// Evenly spaced thumbnails from a YouTube storyboard. Called on the work queue.
    /// Spec: "base_url|w#h#count#columns#rows#interval#name#sig|…"; in the base URL $L is the level, $N the page name (containing $M, the page number).
    static func thumbnails(_ spec: String, frameCount: Int) -> [NSImage] {
        let specs = spec.components(separatedBy: "|")
        guard specs.count >= 2 else { return [] }
        // the 80×45 level is enough and fast (the first level is 48×27, the last is the largest)
        let level = min(2, specs.count - 1)
        let f = specs[level].components(separatedBy: "#")
        guard f.count >= 8, let w = Int(f[0]), let h = Int(f[1]), let total = Int(f[2]), let columns = Int(f[3]), let rows = Int(f[4]),
              total > 0, columns > 0, rows > 0 else { return [] }
        let perPage = columns * rows
        var pages: [Int: CGImage] = [:]
        var result: [NSImage] = []
        for i in 0..<frameCount {
            let k = min(total - 1, Int((Double(i) + 0.5) / Double(frameCount) * Double(total)))
            let s = k / perPage, slot = k % perPage
            if pages[s] == nil {
                let name = f[6].replacingOccurrences(of: "$M", with: "\(s)")
                let address = specs[0].replacingOccurrences(of: "$L", with: "\(level - 1)").replacingOccurrences(of: "$N", with: name)
                    + (f[7].isEmpty ? "" : "&sigh=\(f[7])")
                if let u = URL(string: address), let data = try? Data(contentsOf: u),
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) { pages[s] = cg }
            }
            guard let page = pages[s],
                  let crop = page.cropping(to: CGRect(x: (slot % columns) * w, y: (slot / columns) * h, width: w, height: h)) else { continue }
            result.append(NSImage(cgImage: crop, size: .zero))
        }
        return result
    }
}
