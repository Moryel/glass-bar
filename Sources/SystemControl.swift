import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio

// The real work behind the Touch Bar buttons: key/media events, brightness, keyboard backlight, volume, opening apps.
enum SystemControl {
    // NX_KEYTYPE_* (IOKit/hidsystem/ev_keymap.h)
    enum SpecialKey: Int {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case playPause = 16, next = 17, previous = 18, backlightUp = 21, backlightDown = 22
    }

    /// Media/special key; the system shows its own HUD. Needs Accessibility permission.
    static func postSpecialKey(_ t: SpecialKey) {
        for isPressed in [true, false] {
            let keyState = isPressed ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (t.rawValue << 16) | (keyState << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Keyboard key. If `character` is given, the event carries that character (for shortcuts like ⌘[ on the Turkish Q layout).
    static func pressKey(_ keyCode: CGKeyCode, _ flags: CGEventFlags = [], character: String? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isPressed in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isPressed) else { continue }
            event.flags = flags
            if let character {
                let u = Array(character.utf16)
                event.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            }
            event.post(tap: .cghidEventTap)
        }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Appends a line to ~/Library/Logs/GlassBar.log (for diagnostics).
    static func log(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GlassBar.log")
        guard let data = "\(Date()) \(line)\n".data(using: .utf8), let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        h.write(data)
        try? h.close()
    }

    /// Presses the enabled item bound to ⌘character (⇧⌘ with shift) in the app's menus. Returns true if found.
    /// Called on the work queue; needs Accessibility.
    static func pressMenuShortcut(_ pid: pid_t, _ character: String, shift: Bool) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let menuBar = attribute(appElement, kAXMenuBarAttribute) else { return false }
        let target = character.uppercased()
        // AXMenuItemCmdModifiers: 0 = ⌘ only, 1 = ⇧⌘
        let flags = shift ? 1 : 0
        func search(_ o: AXUIElement, _ depth: Int) -> Bool {
            guard depth < 5, let children = attribute(o, kAXChildrenAttribute) as? [AXUIElement] else { return false }
            for c in children {
                if let k = attribute(c, kAXMenuItemCmdCharAttribute) as? String, k.uppercased() == target,
                   (attribute(c, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0) == flags,
                   attribute(c, kAXEnabledAttribute) as? Bool ?? true {
                    return AXUIElementPerformAction(c, kAXPressAction as CFString) == .success
                }
                if search(c, depth + 1) { return true }
            }
            return false
        }
        return search(menuBar as! AXUIElement, 0)
    }

    private static func attribute(_ o: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(o, name as CFString, &v) == .success ? v : nil
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    static func openSiri() {
        for path in ["/System/Applications/Siri.app", "/System/Library/CoreServices/Siri.app"]
        where FileManager.default.fileExists(atPath: path) { open(path); return }
    }

    /// Launchpad is gone since macOS 26; the same button opens "Apps".
    static func launchpad() {
        open(FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
           ? "/System/Applications/Apps.app" : "/System/Applications/Launchpad.app")
    }

    static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func missionControl() { open("/System/Applications/Mission Control.app") }

    /// For AppleScript and Accessibility reads: the main thread (drawing the bar) never waits.
    static let workQueue = DispatchQueue(label: "GlassBar.work", qos: .userInitiated)

    /// Runs a script in the background.
    static func runScriptInBackground(_ source: String) { workQueue.async { runScript(source) } }

    @discardableResult
    static func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var errorInfo: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
    }
}

// Which Touch Bar: on MacBook Pros from late 2019 on, esc is a physical key and the bar is shorter
// (2008 px = 1004 pt); on earlier models esc is on the bar and the bar is 2170 px = 1085 pt.
enum Hardware {
    static let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var b = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &b, &size, nil, 0)
        return String(cString: b)
    }()

    static let hasPhysicalEsc = ["MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
                              "MacBookPro17,1", "Mac14,7"].contains(model)
    static let width: CGFloat = hasPhysicalEsc ? 1004 : 1085
}

// Built-in display brightness (DisplayServices, private framework).
enum Display {
    private static let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32

    private static var builtInDisplay: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var brightness: Float {
        get {
            guard let f = dlsym(library, "DisplayServicesGetBrightness") else { return 0.5 }
            var v: Float = 0.5
            _ = unsafeBitCast(f, to: GetBrightnessFn.self)(builtInDisplay, &v)
            return v
        }
        set {
            guard let f = dlsym(library, "DisplayServicesSetBrightness") else { return }
            _ = unsafeBitCast(f, to: SetBrightnessFn.self)(builtInDisplay, min(1, max(0, newValue)))
        }
    }
}

// Keyboard backlight (CoreBrightness → KeyboardBrightnessClient, private class).
enum KeyboardBacklight {
    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private static var backlightID: UInt64 {
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let i = client, i.responds(to: sel),
              let ids = i.perform(sel)?.takeUnretainedValue() as? [NSNumber], let first = ids.first
        else { return 1 }
        return first.uint64Value
    }

    static var level: Float {
        get {
            let sel = NSSelectorFromString("brightnessForKeyboard:")
            guard let i = client, i.responds(to: sel) else { return 0.5 }
            typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Float
            return unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, backlightID)
        }
        set {
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            guard let i = client, i.responds(to: sel) else { return }
            typealias F = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
            _ = unsafeBitCast(i.method(for: sel), to: F.self)(i, sel, min(1, max(0, newValue)), backlightID)
        }
    }
}

// Volume of the default output device (CoreAudio).
enum Volume {
    private static var device: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var level: Float {
        get {
            var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioHardwareServiceGetPropertyData(device, &a, 0, nil, &size, &v)
            return v
        }
        set {
            var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var v = Float32(min(1, max(0, newValue)))
            AudioHardwareServiceSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if v > 0, isMuted { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            var a = address(kAudioDevicePropertyMute)
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v)
            return v != 0
        }
        set {
            var a = address(kAudioDevicePropertyMute)
            var v: UInt32 = newValue ? 1 : 0
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        }
    }
}

enum Finder {
    /// Finder label index: 0 none, 1 orange, 2 red, 3 yellow, 4 blue, 5 purple, 6 green, 7 gray.
    static func setLabel(_ index: Int) {
        SystemControl.runScriptInBackground("""
        tell application "Finder"
            repeat with f in (get selection)
                set label index of f to \(index)
            end repeat
        end tell
        """)
    }
}

extension NSImage {
    /// Dominant color of an app icon: the average of its saturated pixels.
    var dominantColor: NSColor {
        let n = 24
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self)
        else { return .systemBlue }
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in 0..<(n * n) {
            let a = Double(data[i * 4 + 3]) / 255
            guard a > 0.6 else { continue }
            let c = NSColor(srgbRed: Double(data[i * 4]) / 255 / a, green: Double(data[i * 4 + 1]) / 255 / a,
                            blue: Double(data[i * 4 + 2]) / 255 / a, alpha: 1)
            let w = c.saturationComponent * c.brightnessComponent
            guard w > 0.12 else { continue }
            r += c.redComponent * w; g += c.greenComponent * w; b += c.blueComponent * w; total += w
        }
        guard total > 0 else { return .systemBlue }
        let c = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        return NSColor(hue: c.hueComponent, saturation: max(0.55, c.saturationComponent),
                       brightness: max(0.8, c.brightnessComponent), alpha: 1)
    }
}
