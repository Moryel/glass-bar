import AppKit
import Carbon

/// GlassBar's own strings: the key is the English text itself, translations live in <language>.lproj/Localizable.strings.
/// Text without a translation (like a mailbox name) is returned as is.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

// Counterpart of the original Keyboard → Touch Bar Settings and Control Strip customization.
enum BarMode: String, CaseIterable {
    case app = "uygulama", expanded = "genis", fKeys = "fTuslari", spaces = "alanlar", quickActions = "hizliEylem"

    var name: String { L(baseName) }

    private var baseName: String {
        switch self {
        case .app: "App Controls"
        case .expanded: "Expanded Control Strip"
        case .fKeys: "F1, F2, etc. Keys"
        case .spaces: "Spaces"
        case .quickActions: "Quick Actions"
        }
    }
}

/// Buttons that can go in the collapsed Control Strip (from the original "Customize Control Strip" list).
enum StripButton: String, CaseIterable {
    case brightness = "parlaklik", volume = "ses", mute = "sessiz", playPause = "oynat", siri, missionControl, launchpad, spotlight,
         notifications = "bildirim", nightShift, screenshot = "ekranResmi", inputSource = "girisKaynagi", desktop = "masaustu",
         screenSaver = "ekranKoruyucu", lockScreen = "kilitle", sleep = "uyut", keyboardBrightness = "klavye", dictation = "dikte",
         quickActions = "hizliEylem"

    var name: String { L(baseName) }

    private var baseName: String {
        switch self {
        case .brightness: "Brightness"
        case .volume: "Volume"
        case .mute: "Mute"
        case .playPause: "Play/Pause"
        case .siri: "Siri"
        case .missionControl: "Mission Control"
        case .launchpad: "Apps"
        case .spotlight: "Spotlight"
        case .notifications: "Notification Center"
        case .nightShift: "Night Shift"
        case .screenshot: "Screenshot"
        case .inputSource: "Input Sources"
        case .desktop: "Show Desktop"
        case .screenSaver: "Screen Saver"
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        case .keyboardBrightness: "Keyboard Brightness"
        case .dictation: "Dictation"
        case .quickActions: "Quick Actions"
        }
    }

    var symbol: String {
        switch self {
        case .brightness: "sun.max.fill"
        case .volume: "speaker.wave.2.fill"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        case .siri: "circle"
        case .missionControl: "rectangle.3.group"
        case .launchpad: "square.grid.3x3.fill"
        case .spotlight: "magnifyingglass"
        case .notifications: "list.bullet.rectangle"
        case .nightShift: "moon.stars.fill"
        case .screenshot: "camera.viewfinder"
        case .inputSource: "globe"
        case .desktop: "menubar.dock.rectangle"
        case .screenSaver: "sparkles.tv"
        case .lockScreen: "lock.fill"
        case .sleep: "powersleep"
        case .keyboardBrightness: "light.max"
        case .dictation: "mic.fill"
        case .quickActions: "gearshape.2"
        }
    }

    static let defaultButtons: [StripButton] = [.brightness, .volume, .mute, .siri]
    static let maxCount = 5
}

/// Shorthand for UserDefaults.
enum Defaults {
    static func string(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
    static func stringArray(_ k: String) -> [String]? { UserDefaults.standard.stringArray(forKey: k) }
    static func bool(_ k: String, _ v: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? v }
    static func set(_ k: String, _ v: Any) { UserDefaults.standard.set(v, forKey: k) }
}

// MARK: system actions of the Control Strip buttons
enum NightShift {
    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    /// CBBlueLightStatus: { BOOL active; BOOL enabled; … }
    static var isOn: Bool {
        get {
            let sel = NSSelectorFromString("getBlueLightStatus:")
            guard let i = client, i.responds(to: sel) else { return false }
            var buffer = [UInt8](repeating: 0, count: 64)
            typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
            _ = buffer.withUnsafeMutableBytes { unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, $0.baseAddress!) }
            return buffer[1] != 0
        }
        set {
            let sel = NSSelectorFromString("setEnabled:")
            guard let i = client, i.responds(to: sel) else { return }
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Bool
            _ = unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, newValue)
        }
    }
}

enum InputSource {
    private static var inputSources: [TISInputSource] {
        let query = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        return TISCreateInputSourceList(query, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func property(_ s: TISInputSource, _ k: CFString) -> AnyObject? {
        guard let p = TISGetInputSourceProperty(s, k) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
    }

    private static func identifier(_ s: TISInputSource) -> String { property(s, kTISPropertyInputSourceID) as? String ?? "" }

    /// Short name of the current keyboard: "TR", "ABC" and so on.
    static var shortName: String {
        let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if identifier(s).hasSuffix(".ABC") || identifier(s).hasSuffix(".US") { return "ABC" }
        if let languages = property(s, kTISPropertyInputSourceLanguages) as? [String], let language = languages.first {
            return language.prefix(2).uppercased()
        }
        return "⌨︎"
    }

    /// The character this key produces in the current keyboard layout (33 → "ğ" on Turkish Q). macOS renames menu
    /// shortcuts to match the layout (⌘[ → ⌘Ğ), so the menu is searched with this character.
    static func character(_ keyCode: CGKeyCode) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let p = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var charCount = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let result = data.withUnsafeBytes { b -> OSStatus in
            UCKeyTranslate(b.bindMemory(to: UCKeyboardLayout.self).baseAddress!, keyCode, UInt16(kUCKeyActionDown), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &charCount, &chars)
        }
        guard result == noErr, charCount > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: charCount)
    }

    static func next() {
        let l = inputSources
        guard !l.isEmpty else { return }
        let current = identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        let i = l.firstIndex { identifier($0) == current } ?? -1
        TISSelectInputSource(l[(i + 1) % l.count])
    }
}

extension SystemControl {
    /// Opens Notification Center by pressing the clock in the menu bar (Accessibility).
    static func openNotificationCenter() {
        guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return }
        let appElement = AXUIElementCreateApplication(cc.processIdentifier)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &menuBar) == .success, let menuBar else { return }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        for o in (children as? [AXUIElement]) ?? [] {
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(o, kAXIdentifierAttribute as CFString, &identifier)
            if (identifier as? String) == "com.apple.menuextra.clock" { AXUIElementPerformAction(o, kAXPressAction as CFString); return }
        }
    }

    static func showDesktop() { run("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"]) }
    static func startScreenSaver() { open("/System/Library/CoreServices/ScreenSaverEngine.app") }
    static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }

    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// Types text as is (emoji, suggestions).
    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var remaining = Array(text.utf16)[...]
        while !remaining.isEmpty {
            let p = Array(remaining.prefix(16))
            remaining = remaining.dropFirst(16)
            for isPressed in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isPressed) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: p.count, unicodeString: p)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Desktop spaces: the count and the current one come from SkyLight; switching uses ⌃1…⌃9.
enum Spaces {
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func state() -> (count: Int, current: Int) {
        typealias ConnectionFn = @convention(c) () -> Int32
        typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        guard let b = dlsym(library, "CGSMainConnectionID"), let k = dlsym(library, "CGSCopyManagedDisplaySpaces"),
              let displays = unsafeBitCast(k, to: CopySpacesFn.self)(unsafeBitCast(b, to: ConnectionFn.self)())?.takeRetainedValue() as? [[String: Any]],
              let display = displays.first,
              let spaces = display["Spaces"] as? [[String: Any]]
        else { return (1, 0) }
        let desktops = spaces.filter { ($0["type"] as? Int) == 0 }
        let currentID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        let i = desktops.firstIndex { ($0["ManagedSpaceID"] as? Int) == currentID } ?? -1
        return (max(1, desktops.count), i)
    }

    static func switchTo(_ i: Int) {
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard i < keyCodes.count else { return }
        SystemControl.pressKey(keyCodes[i], .maskControl, character: "\(i + 1)")
    }
}

/// True Tone-like color temperature: a warm tint multiplied over the bar (the Touch Bar's ambient light sensor isn't accessible).
enum ColorTemperature: String, CaseIterable {
    case off = "kapali", warm = "ilik", warmer = "sicak", nightShift

    var name: String {
        switch self {
        case .off: L("Off")
        case .warm: L("Warm")
        case .warmer: L("Warmer")
        case .nightShift: L("When Night Shift Is On")
        }
    }

    /// Strength of the warm tint (0 = none).
    func intensity(nightShift: Bool) -> Double {
        switch self {
        case .off: 0
        case .warm: 0.5
        case .warmer: 1
        case .nightShift: nightShift ? 1 : 0
        }
    }
}
