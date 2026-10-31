import AppKit
import ServiceManagement
import SwiftUI

// Private APIs to cover the Touch Bar in system-modal mode (DFRFoundation and hidden NSTouchBar class methods).
// MTMR and Pock use the same approach.
enum DFR {
    private static let library = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    static func setControlStripPresence(_ identifier: String, _ show: Bool) {
        typealias F = @convention(c) (CFString, Bool) -> Void
        guard let f = dlsym(library, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(f, to: F.self)(identifier as CFString, show)
    }

    static func setShowsCloseBox(_ show: Bool) {
        typealias F = @convention(c) (Bool) -> Void
        guard let f = dlsym(library, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        unsafeBitCast(f, to: F.self)(show)
    }

    private static func classMethod(_ cls: AnyClass, _ names: [String]) -> (Selector, IMP)? {
        for name in names {
            let sel = NSSelectorFromString(name)
            if let m = class_getClassMethod(cls, sel) { return (sel, method_getImplementation(m)) }
        }
        return nil
    }

    /// placement 1: covers the whole bar (including the Control Strip).
    static func present(_ tb: NSTouchBar, trayIdentifier: String) {
        guard let (sel, imp) = classMethod(NSTouchBar.self, ["presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
                                                              "presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"])
        else { return }
        typealias F = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
        unsafeBitCast(imp, to: F.self)(NSTouchBar.self, sel, tb, 1, trayIdentifier as NSString)
    }

    static func minimize(_ tb: NSTouchBar) { callClassMethod(NSTouchBar.self, ["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"], tb) }
    static func dismiss(_ tb: NSTouchBar) { callClassMethod(NSTouchBar.self, ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"], tb) }
    static func addSystemTrayItem(_ o: NSTouchBarItem) { callClassMethod(NSTouchBarItem.self, ["addSystemTrayItem:"], o) }
    static func removeSystemTrayItem(_ o: NSTouchBarItem) { callClassMethod(NSTouchBarItem.self, ["removeSystemTrayItem:"], o) }

    private static func callClassMethod(_ cls: AnyClass, _ names: [String], _ arg: AnyObject) {
        guard let (sel, imp) = classMethod(cls, names) else { return }
        typealias F = @convention(c) (AnyClass, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: F.self)(cls, sel, arg)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate {
    let state = AppState()
    let modalTouchBar = NSTouchBar()
    let mainItemIdentifier = NSTouchBarItem.Identifier("com.yukselozge.glassbar.ana")
    let trayIdentifier = NSTouchBarItem.Identifier("com.yukselozge.glassbar.tepsi")
    lazy var trayItem: NSCustomTouchBarItem = {
        let o = NSCustomTouchBarItem(identifier: trayIdentifier)
        let b = NSButton(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GlassBar")!,
                         target: self, action: #selector(show))
        o.view = b
        return o
    }()
    var statusItem: NSStatusItem!
    var isMinimized = false
    var observers: [Any] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // for diagnostics: ~/Library/Logs/GlassBar.log
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GlassBar.log")
        try? "\(Date()) launched · Accessibility: \(SystemControl.hasAccessibility ? "yes" : "NO") · model: \(Hardware.model)\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        if !SystemControl.hasAccessibility { SystemControl.requestAccessibility() }
        state.refresh()
        state.frontAppChanged(NSWorkspace.shared.frontmostApplication)
        state.showAppOwnControls = { [weak self] in self?.minimize() }
        AudioCapture.dynamicRange = state.sensitivity.dynamicRange
        AudioCapture.decay = state.smoothness.decay
        state.refreshBackdropImage()

        modalTouchBar.delegate = self
        modalTouchBar.defaultItemIdentifiers = [mainItemIdentifier]
        DFR.addSystemTrayItem(trayItem)
        DFR.setControlStripPresence(trayIdentifier.rawValue, true)
        DFR.setShowsCloseBox(false)
        show()

        setUpStatusMenu()
        UpdateChecker.shared.start()

        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            self.state.frontAppChanged(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            self.applyOwnBarApps()
        })
        observers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state.spaces = Spaces.state()
            if self?.state.backdrop == .wallpaper { self?.state.refreshBackdropImage() }
        })
        // when Spotiw is opened manually and closed with its X, GlassBar comes back instead of the system's old bar
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(Spotiw.identifier + ".didHide"), object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isMinimized else { return }
            self.show()
        })

        // F1–F12 while fn is held
        let fn: (NSEvent) -> Void = { [weak self] e in
            let isPressed = e.modifierFlags.contains(.function)
            if self?.state.fn != isPressed { self?.state.fn = isPressed }
        }
        observers.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: fn) as Any)
        observers.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { fn($0); return $0 } as Any)

        // the physical esc closes the Siri pill and the slider too
        observers.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.state.handleEsc() }
        } as Any)

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.state.refreshNowPlaying()
            self?.state.refreshContact()
            self?.state.refreshCalendar()
            self?.state.refreshSafariVideo()
        }
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.state.refreshSuggestions()
            self?.state.refreshScreenshotTool()
            self?.state.refreshPhotosVideo()
        }
        applyOwnBarApps()

        // for screenshot testing: open GlassBar.app --args -tb2kip genis|parlaklik|ses|siri|fn
        switch UserDefaults.standard.string(forKey: "tb2kip") {
        case "genis": state.panel = .expanded
        case "parlaklik": state.panel = .brightness
        case "ses": state.panel = .volume
        case "siri": DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.state.isSiriActive = true; Microphone.shared.start() }
        case "siriDemo": DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.state.isSiriActive = true }
        case "fn": state.fn = true
        case "emoji": state.panel = .emoji
        case "simdi": state.panel = .nowPlaying
        case "seritDuzenle": state.isEditingControlStrip = true
        case "sekmeler": DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.state.showTabs() }
        default: break
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        DFR.dismiss(modalTouchBar)
        DFR.setControlStripPresence(trayIdentifier.rawValue, false)
        DFR.removeSystemTrayItem(trayItem)
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == mainItemIdentifier else { return nil }
        let o = NSCustomTouchBarItem(identifier: identifier)
        let hostingView = NSHostingView(rootView: TouchBarView(d: state))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let w = hostingView.widthAnchor.constraint(equalToConstant: state.width)
        w.priority = .defaultHigh
        NSLayoutConstraint.activate([w, hostingView.heightAnchor.constraint(equalToConstant: Metrics.barHeight)])
        o.view = hostingView
        return o
    }

    @objc func show() {
        isMinimized = false
        state.refresh()
        DFR.present(modalTouchBar, trayIdentifier: trayIdentifier.rawValue)
    }

    @objc func minimize() {
        isMinimized = true
        DFR.minimize(modalTouchBar)
    }

    /// In apps on the "own Touch Bar" list GlassBar steps aside; it comes back when another app is in front.
    func applyOwnBarApps() {
        if state.ownBarApps.contains(state.frontBundleID) {
            if !isMinimized { minimize() }
        } else if isMinimized {
            show()
        }
    }

    // MARK: menu bar
    /// Monochrome version of the app icon: the bar, two buttons and a wave (template; white/black in the menu bar).
    static func menuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 26, height: 16), flipped: false) { _ in
            let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 24, height: 10), xRadius: 5, yRadius: 5)
            outline.lineWidth = 1.4
            outline.stroke()
            for x in [4.0, 8.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 5.5, width: 3, height: 5), xRadius: 1, yRadius: 1).fill()
            }
            let wave = NSBezierPath()
            for i in 0...24 {
                let u = Double(i) / 24
                let point = NSPoint(x: 12.5 + u * 10, y: 8 + 2.6 * pow(sin(.pi * u), 2) * sin(u * .pi * 3.2))
                i == 0 ? wave.move(to: point) : wave.line(to: point)
            }
            wave.lineWidth = 1.2
            wave.lineCapStyle = .round
            wave.stroke()
            return true
        }
        icon.isTemplate = true
        icon.accessibilityDescription = "GlassBar"
        return icon
    }

    func setUpStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = AppDelegate.menuBarIcon()
        let m = NSMenu()
        m.delegate = self
        statusItem.menu = m
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        if let version = UpdateChecker.shared.latestVersion {
            m.addItem(withTitle: String(format: L("Update available: GlassBar %@…"), version), action: #selector(openUpdatePage), keyEquivalent: "").target = self
            m.addItem(.separator())
        }
        m.addItem(withTitle: L("Show GlassBar"), action: #selector(show), keyEquivalent: "").target = self
        m.addItem(withTitle: L("App's Own Controls"), action: #selector(minimize), keyEquivalent: "").target = self
        m.addItem(.separator())
        if !SystemControl.hasAccessibility {
            m.addItem(withTitle: L("Grant Accessibility Permission…"), action: #selector(requestPermission), keyEquivalent: "").target = self
        }
        if let name = state.frontApp?.localizedName {
            m.addItem(menuItem(String(format: L("Show Own Touch Bar for “%@”"), name), #selector(toggleOwnBar), state.ownBarApps.contains(state.frontBundleID)))
            m.addItem(menuItem(String(format: L("Always Show F1, F2 Keys for “%@”"), name), #selector(toggleAlwaysFKeys), state.alwaysFKeys.contains(state.frontBundleID)))
            m.addItem(.separator())
        }
        m.addItem(submenuItem(L("Touch Bar Shows"), BarMode.allCases.map { g in
            menuItem(g.name, #selector(selectBarMode(_:)), state.barMode == g, g.rawValue)
        }))
        m.addItem(submenuItem(L("Press and Hold fn Key to Show"), BarMode.allCases.map { g in
            menuItem(g.name, #selector(selectFnBarMode(_:)), state.fnBarMode == g, g.rawValue)
        }))
        m.addItem(submenuItem(L("Theme"), Theme.allCases.map { t in
            menuItem(t.name, #selector(temaSec(_:)), state.theme == t, t.rawValue)
        }))
        m.addItem(submenuItem(L("Color Temperature"), ColorTemperature.allCases.map { r in
            menuItem(r.name, #selector(selectColorTemperature(_:)), state.colorTemperature == r, r.rawValue)
        }))
        m.addItem(submenuItem(L("Background"), Backdrop.allCases.map { a in
            menuItem(a.name, #selector(selectBackdrop(_:)), state.backdrop == a, a.rawValue)
        }))
        m.addItem(menuItem(L("Show Control Strip"), #selector(toggleControlStrip), state.showsControlStrip))
        m.addItem(withTitle: L("Customize Control Strip…"), action: #selector(customizeControlStrip), keyEquivalent: "").target = self
        m.addItem(submenuItem(String(format: L("Control Strip Buttons (up to %d)"), StripButton.maxCount), StripButton.allCases.map { t in
            menuItem(t.name, #selector(toggleStripButton(_:)), state.stripButtons.contains(t), t.rawValue)
        }))
        m.addItem(menuItem(L("Show Typing Suggestions"), #selector(toggleSuggestions), state.showsSuggestions))
        m.addItem(submenuItem(L("Spotify player"), [
            menuItem(L("Album cover and sound bar"), #selector(toggleSpotifyPlayer), state.showsSpotifyPlayer),
            menuItem(L("Show album cover"), #selector(toggleArtwork), state.showsArtwork),
            .separator(),
            optionMenu(L("Where to show"), "placement", state.spotifyPlacement),
            optionMenu(L("Sound bar"), "style", state.waveStyle),
            optionMenu(L("Color"), "color", state.waveColor),
            optionMenu(L("Width"), "width", state.waveWidth),
            optionMenu(L("Sensitivity"), "sensitivity", state.sensitivity),
            optionMenu(L("Smoothness"), "smoothness", state.smoothness),
        ]))
        m.addItem(menuItem(L("esc Key on the Bar"), #selector(toggleEsc), state.showsEsc))
        let loginItem = m.addItem(withTitle: L("Open at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(.separator())
        let versionItem = m.addItem(withTitle: String(format: L("GlassBar %@"), UpdateChecker.currentVersion), action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        m.addItem(withTitle: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func menuItem(_ name: String, _ action: Selector, _ isSelected: Bool, _ value: String? = nil) -> NSMenuItem {
        let o = NSMenuItem(title: name, action: action, keyEquivalent: "")
        o.target = self
        o.state = isSelected ? .on : .off
        o.representedObject = value
        return o
    }

    private func submenuItem(_ name: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let o = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        o.submenu = menu
        return o
    }

    @objc func toggleEsc() { state.showsEsc.toggle() }
    @objc func toggleControlStrip() { state.showsControlStrip.toggle() }
    @objc func selectColorTemperature(_ o: NSMenuItem) {
        if let r = ColorTemperature(rawValue: o.representedObject as? String ?? "") { state.colorTemperature = r }
    }

    @objc func selectBackdrop(_ o: NSMenuItem) {
        guard let a = Backdrop(rawValue: o.representedObject as? String ?? "") else { return }
        if a == .customImage { chooseImage() } else { state.backdrop = a }
    }

    /// Lets the user pick a background image (the app runs in the background, so it's activated first).
    func chooseImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = L("Choose an image to show behind the Touch Bar")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        state.backdropImagePath = url.path
        state.backdrop = .customImage
    }
    @objc func toggleSuggestions() { state.showsSuggestions.toggle() }
    @objc func checkForUpdates() { UpdateChecker.shared.check(userInitiated: true) }
    @objc func openUpdatePage() { UpdateChecker.shared.openReleasePage() }
    @objc func toggleSpotifyPlayer() { state.showsSpotifyPlayer.toggle() }
    @objc func toggleArtwork() { state.showsArtwork.toggle() }

    private func optionMenu<T: MenuOption>(_ title: String, _ key: String, _ isSelected: T) -> NSMenuItem {
        submenuItem(title, T.allCases.map { menuItem($0.name, #selector(selectSpotifyOption(_:)), $0 == isSelected, key + ":" + $0.rawValue) })
    }

    @objc func selectSpotifyOption(_ o: NSMenuItem) {
        let p = (o.representedObject as? String ?? "").split(separator: ":").map(String.init)
        guard p.count == 2 else { return }
        switch p[0] {
        case "placement": state.spotifyPlacement = SpotifyPlacement(rawValue: p[1]) ?? state.spotifyPlacement
        case "style": state.waveStyle = WaveStyle(rawValue: p[1]) ?? state.waveStyle
        case "color": state.waveColor = WaveColor(rawValue: p[1]) ?? state.waveColor
        case "width": state.waveWidth = WaveWidth(rawValue: p[1]) ?? state.waveWidth
        case "sensitivity": state.sensitivity = Sensitivity(rawValue: p[1]) ?? state.sensitivity
        case "smoothness": state.smoothness = Smoothness(rawValue: p[1]) ?? state.smoothness
        default: break
        }
    }

    @objc func selectBarMode(_ o: NSMenuItem) {
        if let g = BarMode(rawValue: o.representedObject as? String ?? "") { state.barMode = g; state.panel = .app }
    }

    @objc func temaSec(_ o: NSMenuItem) {
        if let t = Theme(rawValue: o.representedObject as? String ?? "") { state.theme = t }
    }
    @objc func selectFnBarMode(_ o: NSMenuItem) {
        if let g = BarMode(rawValue: o.representedObject as? String ?? "") { state.fnBarMode = g }
    }

    @objc func customizeControlStrip() {
        state.panel = .app
        state.isEditingControlStrip = true
    }

    /// The chosen button is appended; past the limit the oldest one is removed.
    @objc func toggleStripButton(_ o: NSMenuItem) {
        guard let t = StripButton(rawValue: o.representedObject as? String ?? "") else { return }
        var l = state.stripButtons
        if let i = l.firstIndex(of: t) { l.remove(at: i) } else { l.append(t); if l.count > StripButton.maxCount { l.removeFirst() } }
        state.stripButtons = l
    }

    @objc func toggleOwnBar() {
        let p = state.frontBundleID
        if let i = state.ownBarApps.firstIndex(of: p) { state.ownBarApps.remove(at: i) } else { state.ownBarApps.append(p) }
        applyOwnBarApps()
    }

    @objc func toggleAlwaysFKeys() {
        let p = state.frontBundleID
        if let i = state.alwaysFKeys.firstIndex(of: p) { state.alwaysFKeys.remove(at: i) } else { state.alwaysFKeys.append(p) }
    }

    @objc func requestPermission() {
        SystemControl.requestAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleLaunchAtLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }
}

/// Spotiw (github.com/Moryel/spotiw): a separate app that shows a Spotify player on the Touch Bar.
/// When its bar closes it posts a distributed "didHide" notification; GlassBar then comes back.
enum Spotiw {
    static let identifier = "com.yuksel.spotiw"
}

// The app used to be called TouchBar2: on first launch, copy settings over from the old identifier.
let legacyDomain = "com.yukselozge.TouchBar2"
if !UserDefaults.standard.bool(forKey: "ayarlarTasindi") {
    for (key, value) in UserDefaults.standard.persistentDomain(forName: legacyDomain) ?? [:]
    where UserDefaults.standard.object(forKey: key) == nil {
        UserDefaults.standard.set(value, forKey: key)
    }
    UserDefaults.standard.set(true, forKey: "ayarlarTasindi")
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
