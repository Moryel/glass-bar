import AppKit

// Video open in Photos: the player's scrubber and times are read through Accessibility; seeking writes to the scrubber.
// For thumbnails the video is exported from Photos to a temporary folder (AppleScript; Automation permission on first use).
struct PhotosVideo: Equatable {
    var position: Float
    var elapsed: String
    var remaining: String
    /// which video (thumbnails are regenerated when it changes): like "28 Oct 2026 18:51, Duration 1:40"
    var identifier: String
}

enum PhotosPlayer {
    static let bundleID = "com.apple.Photos"

    private static func canvas(_ pid: pid_t) -> AXUIElement? {
        guard let w = AX.attribute(AX.appElement(pid), kAXFocusedWindowAttribute) else { return nil }
        return AX.search(w as! AXUIElement, 6) { AX.attribute($0, kAXIdentifierAttribute) as? String == "IPXCanvasItemView" }
    }

    private static func scrubber(_ canvas: AXUIElement) -> AXUIElement? {
        AX.children(canvas).first { AX.attribute($0, kAXIdentifierAttribute) as? String == "slider_scrubber" }
    }

    /// "01:16", "‎−00:24", "1:02:03" → seconds
    private static func seconds(_ s: String) -> Double {
        s.filter { $0.isNumber || $0 == ":" }.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    /// Called on the work queue. nil if no video is open.
    static func read(_ pid: pid_t) -> PhotosVideo? {
        guard let t = canvas(pid), scrubber(t) != nil else { return nil }
        let c = AX.children(t)
        let labels = c.filter { AX.attribute($0, kAXRoleAttribute) as? String == "AXStaticText" }
            .compactMap { AX.attribute($0, kAXValueAttribute) as? String }
        guard labels.count >= 2 else { return nil }
        let identifier = c.compactMap { o -> String? in
            guard AX.attribute(o, kAXRoleAttribute) as? String == "AXGroup" else { return nil }
            return AX.attribute(o, kAXDescriptionAttribute) as? String
        }.first ?? ""
        let g = seconds(labels[0]), k = seconds(labels[1])
        return PhotosVideo(position: g + k > 0 ? Float(g / (g + k)) : 0, elapsed: labels[0], remaining: labels[1], identifier: identifier)
    }

    /// Seeks the video to a position between 0 and 1.
    static func scrub(_ pid: pid_t, _ fraction: Float) {
        guard let t = canvas(pid), let s = scrubber(t) else { return }
        let result = AXUIElementSetAttributeValue(s, kAXValueAttribute as CFString, NSNumber(value: Double(fraction)))
        if result != .success { SystemControl.log("photos scrub: \(result.rawValue)") }
    }

    static func playPause(_ pid: pid_t) { AX.pressWindowButton(pid, "button_playPause") }

    /// Exports the selected video to a temporary folder and returns the file path. Called on the work queue.
    static func exportSelection() -> String? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GlassBar-photos")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SystemControl.runScript("""
        tell application "Photos"
            set s to selection
            if (count s) = 0 then return
            export {item 1 of s} to (POSIX file "\(folder.path)")
        end tell
        """)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }?.path
    }
}
