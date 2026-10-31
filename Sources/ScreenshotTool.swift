import AppKit

// ⇧⌘5 screenshot tool: while it's open the bar shows the capture/record buttons and "Save to" like the original.
// The buttons press the tool's own buttons through Accessibility; the selected mode and save location are read from the tool's preferences.
struct ScreenshotTool: Equatable {
    /// display, window, selection
    var style = "display"
    var video = false
    var target = "Desktop"

    static let bundleID = "com.apple.screencaptureui"

    /// The tool's button identifiers (SF Symbols names) in order: three capture modes, then three recording modes.
    static let captureModes: [(identifier: String, style: String)] = [
        ("menubar.dock.rectangle", "display"), ("macwindow", "window"), ("rectangle.dashed", "selection")]
    static let recordModes: [(identifier: String, style: String)] = [
        ("menubar.dock.rectangle.badge.record", "display"), ("macwindow.badge.record", "window"),
        ("rectangle.dashed.badge.record", "selection")]

    /// The button's symbol: "macwindow.badge.record" doesn't exist in SF Symbols; the original Touch Bar shows a window with a cursor.
    static func symbol(_ identifier: String) -> String {
        identifier == "macwindow.badge.record" ? "macwindow.and.cursorarrow" : identifier
    }
    /// Save locations in the "Options" menu, in menu order (shown in the system language through L())
    static let targets = ["Desktop", "Documents", "Clipboard", "Mail", "Preview", "Other Location…"]

    /// Whether the tool is on screen (the process can stay alive; it counts as open if it has a window on screen). Main thread, cheap.
    static func isOnScreen() -> Bool {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let pid = a.processIdentifier
        guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return l.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
    }

    /// Selected mode and save location from the tool's preferences.
    static func read() -> ScreenshotTool {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        func value(_ k: String) -> Any? { CFPreferencesCopyAppValue(k as CFString, domain) }
        var d = ScreenshotTool()
        d.style = value("style") as? String ?? "display"
        d.video = (value("video") as? Int ?? 0) != 0
        switch value(d.video ? "target-screenrecording" : "target-screenshot") as? String ?? "file" {
        case "clipboard": d.target = "Clipboard"
        case "mail": d.target = "Mail"
        case "preview": d.target = "Preview"
        default:
            let path = (value("location") as? String).map { ($0 as NSString).expandingTildeInPath } ?? ""
            let home = NSHomeDirectory()
            if path.isEmpty || path == home + "/Desktop" { d.target = "Desktop" }
            else if path == home + "/Documents" { d.target = "Documents" }
            else { d.target = FileManager.default.displayName(atPath: path) }
        }
        return d
    }

    // MARK: the tool's buttons (on the work queue)
    private static var appElement: AXUIElement? {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let u = AXUIElementCreateApplication(a.processIdentifier)
        AXUIElementSetMessagingTimeout(u, 0.5)
        return u
    }

    private static func attribute(_ o: AXUIElement, _ k: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, k as CFString, &v) == .success ? v : nil
    }

    /// First element in the tree matching the predicate (the tool is small: window → group → buttons, menu items under the window).
    private static func find(_ o: AXUIElement, _ d: Int = 0, _ predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        if predicate(o) { return o }
        guard d < 4, let c = attribute(o, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for x in c { if let b = find(x, d + 1, predicate) { return b } }
        return nil
    }

    static func press(_ identifier: String) {
        guard let u = appElement, let b = find(u, 0, { attribute($0, kAXIdentifierAttribute) as? String == identifier }) else { return }
        AXUIElementPerformAction(b, kAXPressAction as CFString)
    }

    static func close() { press("multiply.circle.fill") }

    /// Opens the Options menu and picks the save location. The item is found by its position in the menu, not its title
    /// (identifiers: save locations "optionsSaveTo:", the last one "showOtherPicker:"), so it works in every language.
    static func selectTarget(_ name: String) {
        guard let u = appElement, let index = targets.firstIndex(of: name),
              let m = find(u, 0, { attribute($0, kAXRoleAttribute) as? String == "AXMenuButton" }) else { return }
        AXUIElementPerformAction(m, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.3)
        var items: [AXUIElement] = []
        func collect(_ o: AXUIElement, _ d: Int) {
            let id = attribute(o, kAXIdentifierAttribute) as? String
            if id == "optionsSaveTo:" || id == "showOtherPicker:" { items.append(o) }
            guard d < 3 else { return }
            for c in attribute(o, kAXChildrenAttribute) as? [AXUIElement] ?? [] { collect(c, d + 1) }
        }
        collect(u, 0)
        if index < items.count {
            AXUIElementPerformAction(items[index], kAXPressAction as CFString)
        } else {
            AXUIElementPerformAction(m, kAXCancelAction as CFString)
        }
    }
}
