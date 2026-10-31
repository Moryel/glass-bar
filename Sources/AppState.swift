import AppKit
import SwiftUI

// State of the bar and the actions behind its buttons.
final class AppState: ObservableObject {
    /// Temporary panels; while `.app`, the bar follows the configured bar mode.
    enum Panel { case app, expanded, brightness, volume, nowPlaying, emoji, tabs }

    @Published var panel = Panel.app
    @Published var fn = false
    @Published var isSiriActive = false
    @Published var brightness: Float = 0.5
    @Published var volume: Float = 0.5
    @Published var isMuted = false
    @Published var isNightShiftOn = false
    @Published var inputSourceName = ""
    @Published var frontApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    @Published var appColor = Color.blue
    @Published var nowPlaying: NowPlaying?
    @Published var nowPlayingProgress: Float = 0
    @Published var suggestions = Suggestions()
    @Published var emojiCategory = 1
    @Published var spaces = (count: 1, current: 0)
    @Published var tabs: [SafariTab] = []
    /// Safari window shown in the tab strip (1 = frontmost)
    @Published var selectedWindow = 1
    @Published var isLoadingTabs = false
    @Published var isSafariAccessDenied = false
    /// the open popover
    @Published var popover: Popover?
    /// item under the finger while pressing and sliding
    @Published var highlightedPopoverItem: Int?
    @Published var isDraggingPopover = false
    /// frame of the popover's item group in the bar (to find which item the finger is on)
    var popoverFrame: CGRect = .zero
    /// month shown in Calendar (first day of the month)
    /// Calendar's view: day, week or month (the year view also gets the month strip).
    @Published var calendarUnit = Calendar.Component.month
    @Published var calendarDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    /// contact selected in Contacts
    @Published var contact: Contact?
    /// video open in Photos
    @Published var photosVideo: PhotosVideo?
    /// video playing in Safari
    @Published var safariVideo: SafariVideo?
    private var safariStoryboardKey = ""
    private var photosVideoID = ""
    /// set while the ⇧⌘5 tool is open; the bar shows its buttons
    @Published var screenshotTool: ScreenshotTool?
    /// the "Save to" list is open
    @Published var showsTargetList = false
    /// slider shown while pressing and sliding
    @Published var liveSlider: Panel?
    /// frames of the brightness/volume buttons in the bar (the pop-up slider opens to their left)
    var buttonFrames: [Panel: CGRect] = [:]

    // MARK: settings
    @Published var theme = Theme(rawValue: Defaults.string("tema")) ?? .classic { didSet { Defaults.set("tema", theme.rawValue) } }
    /// Behind the glass; starts off if the old "Ambient light" setting was off
    @Published var colorTemperature = ColorTemperature(rawValue: Defaults.string("renkSicakligi")) ?? .off {
        didSet { Defaults.set("renkSicakligi", colorTemperature.rawValue) }
    }
    @Published var backdrop = Backdrop(rawValue: Defaults.string("arkaPlan")) ?? (Defaults.bool("ortamIsigi", true) ? .app : .off) {
        didSet { Defaults.set("arkaPlan", backdrop.rawValue); refreshBackdropImage() }
    }
    /// file picked with "Choose Image…"
    @Published var backdropImagePath = Defaults.string("arkaGorsel") { didSet { Defaults.set("arkaGorsel", backdropImagePath); refreshBackdropImage() } }
    /// bar-sized strip of the wallpaper or the image
    @Published var backdropImage: NSImage?
    @Published var showsEsc = Defaults.bool("escGoster", !Hardware.hasPhysicalEsc) { didSet { Defaults.set("escGoster", showsEsc) } }
    @Published var barMode = BarMode(rawValue: Defaults.string("gosterim")) ?? .app { didSet { Defaults.set("gosterim", barMode.rawValue) } }
    @Published var fnBarMode = BarMode(rawValue: Defaults.string("fnBasili")) ?? .fKeys { didSet { Defaults.set("fnBasili", fnBarMode.rawValue) } }
    @Published var showsControlStrip = Defaults.bool("seritGoster", true) { didSet { Defaults.set("seritGoster", showsControlStrip) } }
    @Published var showsSuggestions = Defaults.bool("oneriAcik", true) { didSet { Defaults.set("oneriAcik", showsSuggestions); if !showsSuggestions { suggestions = Suggestions() } } }
    /// Control Strip editing mode ("Customize Control Strip…" in the menu).
    @Published var isEditingControlStrip = false
    @Published var stripButtons = (Defaults.stringArray("seritTuslari") ?? []).compactMap(StripButton.init(rawValue:)).nilIfEmpty ?? StripButton.defaultButtons {
        didSet { Defaults.set("seritTuslari", stripButtons.map(\.rawValue)) }
    }
    /// apps that show their own Touch Bar
    @Published var ownBarApps = Defaults.stringArray("kendiCubugu") ?? [] { didSet { Defaults.set("kendiCubugu", ownBarApps) } }
    /// apps that always show F1–F12
    @Published var alwaysFKeys = Defaults.stringArray("hepF") ?? [] { didSet { Defaults.set("hepF", alwaysFKeys) } }

    let width = Hardware.width
    /// Shows the front app's own Touch Bar controls (GlassBar minimizes).
    var showAppOwnControls: () -> Void = {}
    /// Spotify player with album art (when off, a plain track bar like in Music).
    @Published var showsSpotifyPlayer = Defaults.bool("spotifyOynatici", true) { didSet { Defaults.set("spotifyOynatici", showsSpotifyPlayer) } }
    @Published var showsArtwork = Defaults.bool("kapakGoster", true) { didSet { Defaults.set("kapakGoster", showsArtwork) } }
    @Published var spotifyPlacement = SpotifyPlacement(rawValue: Defaults.string("spotifyYeri")) ?? .desktop { didSet { Defaults.set("spotifyYeri", spotifyPlacement.rawValue) } }
    @Published var waveStyle = WaveStyle(rawValue: Defaults.string("dalgaStili")) ?? .bars { didSet { Defaults.set("dalgaStili", waveStyle.rawValue) } }
    @Published var waveColor = WaveColor(rawValue: Defaults.string("dalgaRengi")) ?? .artwork { didSet { Defaults.set("dalgaRengi", waveColor.rawValue) } }
    @Published var waveWidth = WaveWidth(rawValue: Defaults.string("dalgaGenisligi")) ?? .medium { didSet { Defaults.set("dalgaGenisligi", waveWidth.rawValue) } }
    @Published var sensitivity = Sensitivity(rawValue: Defaults.string("hassasiyet")) ?? .normal {
        didSet { Defaults.set("hassasiyet", sensitivity.rawValue); AudioCapture.dynamicRange = sensitivity.dynamicRange }
    }
    @Published var smoothness = Smoothness(rawValue: Defaults.string("yumusaklik")) ?? .normal {
        didSet { Defaults.set("yumusaklik", smoothness.rawValue); AudioCapture.decay = smoothness.decay }
    }

    /// Whether to show the Spotify player while Spotify plays and another app is in front (on the desktop or everywhere, per setting).
    var showsSpotifyHere: Bool {
        guard showsSpotifyPlayer, let c = nowPlaying, c.source == NowPlaying.spotify, c.isPlaying, frontBundleID != NowPlaying.spotify else { return false }
        return spotifyPlacement == .everywhere || (spotifyPlacement == .desktop && frontBundleID == "com.apple.finder")
    }

    private var closeTimer: Timer?
    private var siriTimer: Timer?
    private var lastScrub = Date.distantPast
    private var liveSliderStart: Float = 0

    var frontBundleID: String { frontApp?.bundleIdentifier ?? "" }

    /// While fn is held, the fn setting; in apps on the "always F keys" list, F keys; otherwise the bar mode setting.
    var activeBarMode: BarMode {
        if fn { return fnBarMode }
        if alwaysFKeys.contains(frontBundleID) { return .fKeys }
        return barMode
    }

    var animationKey: String { "\(activeBarMode)\(panel)\(isSiriActive)\(frontBundleID)\(showsEsc)\(showsControlStrip)\(liveSlider.map { "\($0)" } ?? "")\(nowPlaying != nil)\(suggestions.isActive)\(suggestionsHidden)\(emojiCategory)\(popover != nil)\(isEditingControlStrip)" }

    // MARK: esc, fn
    func esc() {
        handleEsc()
        SystemControl.pressKey(53)
    }

    /// esc (on the bar or physical) closes the open Siri pill and temporary panels.
    func handleEsc() {
        if popover != nil { closePopover(); return }
        if isEditingControlStrip { isEditingControlStrip = false; return }
        if screenshotTool != nil { SystemControl.workQueue.async { ScreenshotTool.close() } }
        if isSiriActive { stopSiri() }
        if panel != .app && panel != .expanded { panel = .app }
    }

    func pressFunctionKey(_ i: Int) {
        let keyCodes: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        // ⌃⌥⇧⌘ held on the keyboard are added too (like fn+⌃+F3)
        let heldModifiers = CGEventSource.flagsState(.hidSystemState).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        SystemControl.pressKey(keyCodes[i - 1], heldModifiers.union(.maskSecondaryFn))
    }

    // MARK: Control Strip
    func expand() { refresh(); panel = .expanded }
    func collapse() { panel = .app }

    func showSlider(_ k: Panel) {
        refresh()
        panel = k
        scheduleSliderClose()
    }

    /// If the slider stays open, it closes after a while without touches (like the original).
    private func scheduleSliderClose() {
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, self.panel == .brightness || self.panel == .volume else { return }
            self.panel = .app
        }
    }

    func setBrightness(_ v: Float) { Display.brightness = v; scheduleSliderClose() }

    func setVolume(_ v: Float) {
        Volume.level = v
        isMuted = false
        scheduleSliderClose()
    }

    /// Pressing the brightness/volume button and sliding without lifting: a slider appears over the button and the value changes live.
    func liveSlide(_ k: Panel, _ dx: CGFloat) {
        if liveSlider == nil {
            refresh()
            liveSliderStart = k == .brightness ? brightness : volume
            liveSlider = k
        }
        let v = min(1, max(0, liveSliderStart + Float(dx / 320)))
        if k == .brightness { brightness = v; Display.brightness = v } else { volume = v; Volume.level = v; isMuted = false }
    }

    func endLiveSlider() { liveSlider = nil }

    /// Icons at the ends of the pop-up slider: steps of 1/16 (the system's own step).
    func sliderStep(_ k: Panel, _ direction: Float) {
        if k == .brightness {
            brightness = min(1, max(0, brightness + direction / 16))
            Display.brightness = brightness
        } else {
            volume = min(1, max(0, volume + direction / 16))
            Volume.level = volume
            isMuted = false
        }
        scheduleSliderClose()
    }

    func toggleMute() {
        if SystemControl.hasAccessibility { SystemControl.postSpecialKey(.mute) } else { Volume.isMuted.toggle() }
        refreshSoon()
    }

    /// Step buttons send media keys so the system shows its own HUD; without permission they set the value directly.
    func step(_ t: SystemControl.SpecialKey) {
        if SystemControl.hasAccessibility {
            SystemControl.postSpecialKey(t)
        } else {
            let d: Float = 1 / 16
            switch t {
            case .brightnessUp: Display.brightness += d
            case .brightnessDown: Display.brightness -= d
            case .volumeUp: Volume.level += d
            case .volumeDown: Volume.level -= d
            case .backlightUp: KeyboardBacklight.level += d
            case .backlightDown: KeyboardBacklight.level -= d
            case .mute: Volume.isMuted.toggle()
            case .playPause: nowPlaying?.playPause()
            case .next: nowPlaying?.next()
            case .previous: nowPlaying?.previous()
            }
        }
        refreshSoon()
    }

    func performStripButton(_ t: StripButton) {
        switch t {
        case .brightness: showSlider(.brightness)
        case .volume: showSlider(.volume)
        case .mute: toggleMute()
        case .playPause: if let nowPlaying { nowPlaying.playPause(); refreshSoon() } else { step(.playPause) }
        case .siri: toggleSiri()
        case .missionControl: SystemControl.missionControl()
        case .launchpad: SystemControl.launchpad()
        case .spotlight: SystemControl.pressKey(49, .maskCommand, character: " ")
        case .notifications: SystemControl.openNotificationCenter()
        case .nightShift: NightShift.isOn.toggle(); isNightShiftOn = NightShift.isOn
        case .screenshot: SystemControl.pressKey(23, [.maskCommand, .maskShift], character: "5")
        case .inputSource: InputSource.next(); inputSourceName = InputSource.shortName
        case .desktop: SystemControl.showDesktop()
        case .screenSaver: SystemControl.startScreenSaver()
        case .lockScreen: SystemControl.pressKey(12, [.maskCommand, .maskControl], character: "q")
        case .sleep: SystemControl.sleepNow()
        case .keyboardBrightness:
            showPopover(Popover(items: [PopoverItem(symbol: "light.min") { self.step(.backlightDown) },
                                     PopoverItem(symbol: "light.max") { self.step(.backlightUp) }]))
        case .dictation: menu("startDictation:")
        case .quickActions: showSubmenu(nil, ["Servisler", "Services"], title: "Quick Actions")
        }
    }

    func refresh() {
        brightness = Display.brightness
        volume = Volume.level
        isMuted = Volume.isMuted
        isNightShiftOn = NightShift.isOn
        inputSourceName = InputSource.shortName
        spaces = Spaces.state()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
            self?.refreshNowPlaying()
        }
    }

    // MARK: Siri
    func toggleSiri() { isSiriActive ? stopSiri() : startSiri() }

    func startSiri() {
        SystemControl.openSiri()
        panel = .app
        isSiriActive = true
        Microphone.shared.start()
        siriTimer?.invalidate()
        siriTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.stopSiri() }
    }

    func stopSiri() {
        siriTimer?.invalidate()
        if isSiriActive { Microphone.shared.stop() }
        isSiriActive = false
    }

    // MARK: front app
    func frontAppChanged(_ a: NSRunningApplication?) {
        guard let a, a.activationPolicy == .regular, a.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        // when the same app comes to the front again (e.g. after a permission dialog), keep open panels
        let isSameApp = a.bundleIdentifier == frontApp?.bundleIdentifier
        frontApp = a
        if isSameApp { return }
        closePopover()
        contact = nil
        appColor = Color(nsColor: a.icon?.dominantColor ?? .systemBlue)
        if a.bundleIdentifier != "com.apple.Siri" { stopSiri() }
        if panel == .emoji || panel == .tabs { panel = .app }
        suggestions = Suggestions()
        refreshNowPlaying()
    }

    // MARK: Now Playing
    private var isReadingNowPlaying = false
    private var isReadingSuggestions = false

    func refreshNowPlaying() {
        guard !isReadingNowPlaying else { return }
        isReadingNowPlaying = true
        let front = frontBundleID
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        SystemControl.workQueue.async {
            let c = NowPlaying.read(frontBundleID: front, runningBundleIDs: runningBundleIDs)
            DispatchQueue.main.async {
                self.isReadingNowPlaying = false
                self.applyNowPlaying(c)
            }
        }
    }

    private func applyNowPlaying(_ c: NowPlaying?) {
        if c != nowPlaying { nowPlaying = c }
        Filmstrip.shared.load(c?.video == true ? c?.filePath : nil)
        Artwork.shared.load(showsSpotifyPlayer ? c?.artworkURL : nil)
        // the sound bar listens to Spotify's audio only while the Spotify player is visible and playing
        AudioCapture.shared.update(isOn: showsSpotifyPlayer && c?.source == NowPlaying.spotify && c?.isPlaying == true
                                       && (frontBundleID == NowPlaying.spotify || showsSpotifyHere || panel == .nowPlaying))
        if let c, Date().timeIntervalSince(lastScrub) > 1.5 { nowPlayingProgress = Float(c.position / c.duration) }
        if c == nil && panel == .nowPlaying { panel = .app }
    }

    /// Seeks at most ~7 times a second while dragging; on lift, `force` jumps to the final position.
    func scrubNowPlaying(_ v: Float, force: Bool = false) {
        guard let c = nowPlaying, force || Date().timeIntervalSince(lastScrub) > 0.15 else { return }
        lastScrub = Date()
        c.seek(Double(v) * c.duration)
    }

    func nowPlayingCommand(_ k: (NowPlaying) -> Void) {
        guard let c = nowPlaying else { return }
        k(c)
        refreshSoon()
    }

    // MARK: screenshot tool
    /// From the timer in main.swift; the bar changes when the tool opens/closes.
    func refreshScreenshotTool() {
        let isOn = ScreenshotTool.isOnScreen()
        if !isOn {
            if screenshotTool != nil { screenshotTool = nil; showsTargetList = false }
            return
        }
        let d = ScreenshotTool.read()
        if d != screenshotTool { screenshotTool = d }
    }

    func selectScreenshotMode(_ identifier: String, style: String, video: Bool) {
        screenshotTool?.style = style
        screenshotTool?.video = video
        SystemControl.workQueue.async { ScreenshotTool.press(identifier) }
    }

    func selectScreenshotTarget(_ name: String) {
        showsTargetList = false
        if name != "Other Location…" { screenshotTool?.target = name }
        SystemControl.workQueue.async { ScreenshotTool.selectTarget(name) }
    }

    // MARK: popover
    func showPopover(_ a: Popover) {
        highlightedPopoverItem = nil
        popover = a
    }

    func closePopover() {
        popover = nil
        highlightedPopoverItem = nil
        isDraggingPopover = false
    }

    /// Press and slide: opens the popover if needed and highlights the item under the finger.
    func dragPopover(_ x: CGFloat, _ makePopover: () -> Popover) {
        if !isDraggingPopover { isDraggingPopover = true }
        if popover == nil { showPopover(makePopover()) }
        guard let n = popover?.items.count, n > 0, n <= 8, popoverFrame.width > 0 else { return }
        let i = Int(floor((x - popoverFrame.minX) / (popoverFrame.width / CGFloat(n))))
        let highlighted = (0..<n).contains(i) ? i : nil
        if highlighted != highlightedPopoverItem { highlightedPopoverItem = highlighted }
    }

    /// On lift, the item under the finger is chosen; lifting outside the items keeps the popover open.
    func releasePopoverDrag() {
        isDraggingPopover = false
        guard let a = popover, let i = highlightedPopoverItem, i < a.items.count else { highlightedPopoverItem = nil; return }
        closePopover()
        a.items[i].action()
    }

    // MARK: menu commands
    /// Presses a menu item of the front app: by its identifier or by one of its titles.
    func menu(_ identifier: String? = nil, _ titles: String...) {
        guard let pid = frontApp?.processIdentifier else { return }
        SystemControl.workQueue.async {
            let didPress = AX.pressMenuItem(pid, identifier: identifier, titles: titles)
            SystemControl.log("menu \(identifier ?? titles.first ?? ""): \(didPress ? "ok" : "not found")")
        }
    }

    /// Shows a submenu's items (Mail mailboxes, flag colors, Services) in a popover.
    func showSubmenu(_ identifier: String?, _ titles: [String], title: String) {
        guard let pid = frontApp?.processIdentifier else { return }
        showPopover(Popover(title: title, items: [], placeholder: "Loading…"))
        SystemControl.workQueue.async {
            let l = AX.submenuTitles(pid, identifier: identifier, titles: titles)
            DispatchQueue.main.async {
                guard self.popover?.title == title else { return }
                self.popover = Popover(title: title, items: l.map { t in
                    PopoverItem(text: t) { SystemControl.workQueue.async { AX.pressSubmenuItem(pid, identifier: identifier, titles: titles, t) } }
                }, placeholder: "Nothing to choose right now")
            }
        }
    }

    /// Presses a button in the front window (Calculator).
    func pressWindowButton(_ identifier: String) {
        guard let pid = frontApp?.processIdentifier else { return }
        SystemControl.workQueue.async { AX.pressWindowButton(pid, identifier) }
    }

    // MARK: Calendar
    func showCalendarDate(_ month: Date) {
        calendarDate = month
        let c = Calendar.current.dateComponents([.year, .month, .day], from: month)
        SystemControl.runScriptInBackground("""
        set g to current date
        set day of g to 1
        set year of g to \(c.year ?? 2026)
        set month of g to \(c.month ?? 1)
        set day of g to \(calendarUnit == .month ? 1 : c.day ?? 1)
        tell application "Calendar" to view calendar at g
        """)
    }

    func showCalendarToday() {
        calendarDate = AppState.startOfUnit(Date(), calendarUnit)
        SystemControl.runScriptInBackground("tell application \"Calendar\" to view calendar at (current date)")
    }

    static func startOfUnit(_ t: Date, _ b: Calendar.Component) -> Date {
        let c = Calendar.current
        switch b {
        case .day: return c.startOfDay(for: t)
        case .weekOfYear: return c.dateInterval(of: .weekOfYear, for: t)?.start ?? t
        default: return c.date(from: c.dateComponents([.year, .month], from: t)) ?? t
        }
    }

    /// From the timer in main.swift; while Calendar is in front, reads the unit checked in the View menu.
    func refreshCalendar() {
        guard frontBundleID == "com.apple.iCal", panel == .app, let pid = frontApp?.processIdentifier else { return }
        SystemControl.workQueue.async {
            let b: Calendar.Component = AX.isChecked(pid, "Gün") ? .day : AX.isChecked(pid, "Hafta") ? .weekOfYear : .month
            DispatchQueue.main.async {
                guard b != self.calendarUnit else { return }
                self.calendarUnit = b
                self.calendarDate = AppState.startOfUnit(self.calendarDate, b)
            }
        }
    }

    // MARK: Contacts
    /// From the timer in main.swift; reads the selected contact only while Contacts is in front.
    func refreshContact() {
        guard frontBundleID == Contact.bundleID, panel == .app else { return }
        SystemControl.workQueue.async {
            let k = Contact.read()
            DispatchQueue.main.async { if k != self.contact { self.contact = k } }
        }
    }

    // MARK: Photos video
    /// From the timer in main.swift; reads the player only while Photos is in front.
    func refreshPhotosVideo() {
        guard frontBundleID == PhotosPlayer.bundleID, panel == .app, let pid = frontApp?.processIdentifier else {
            if photosVideo != nil { photosVideo = nil }
            return
        }
        SystemControl.workQueue.async {
            let v = PhotosPlayer.read(pid)
            DispatchQueue.main.async {
                // don't let a stale position read during a drag pull the playhead back
                if var v, Date().timeIntervalSince(self.lastScrub) < 1.5, let old = self.photosVideo { v.position = old.position; self.photosVideo = v }
                else if v != self.photosVideo { self.photosVideo = v }
                guard let v, v.identifier != self.photosVideoID else { return }
                self.photosVideoID = v.identifier
                Filmstrip.photos.load(nil)
                SystemControl.workQueue.async {
                    let path = PhotosPlayer.exportSelection()
                    SystemControl.log("photos video: \(path == nil ? "export failed" : "exported")")
                    DispatchQueue.main.async { if self.photosVideoID == v.identifier { Filmstrip.photos.load(path) } }
                }
            }
        }
    }

    /// Seeks at most ~7 times a second while dragging; on lift, `force` jumps to the final position.
    func scrubPhotosVideo(_ v: Float, force: Bool = false) {
        guard let pid = frontApp?.processIdentifier, force || Date().timeIntervalSince(lastScrub) > 0.15 else { return }
        lastScrub = Date()
        SystemControl.workQueue.async { PhotosPlayer.scrub(pid, v) }
    }

    // MARK: backdrop
    /// Prepares the strip when wallpaper/image is selected (at launch, on selection change, on desktop change).
    func refreshBackdropImage() {
        let url: URL? = switch backdrop {
        case .wallpaper: Backdrop.wallpaperURL
        case .customImage: backdropImagePath.isEmpty ? nil : URL(fileURLWithPath: backdropImagePath)
        default: nil
        }
        guard let url else { backdropImage = nil; return }
        let w = width
        SystemControl.workQueue.async {
            let r = Backdrop.strip(url, width: w)
            if r == nil { SystemControl.log("backdrop: couldn't read image (\(url.lastPathComponent))") }
            DispatchQueue.main.async { self.backdropImage = r }
        }
    }

    // MARK: Safari video
    /// From the timer in main.swift; reads the page's video only while Safari is in front. If a video has started
    /// (or is playing), the Safari bar turns into a player.
    func refreshSafariVideo() {
        guard frontBundleID == "com.apple.Safari", panel == .app, !isSiriActive else {
            if safariVideo != nil { safariVideo = nil }
            return
        }
        SystemControl.workQueue.async {
            var v = SafariPlayer.read()
            if let x = v, x.isPaused && x.elapsed < 0.5 { v = nil }
            DispatchQueue.main.async {
                if var v, Date().timeIntervalSince(self.lastScrub) < 1.5, let old = self.safariVideo { v.position = old.position; self.safariVideo = v }
                else if v != self.safariVideo { self.safariVideo = v }
                guard let v else { return }
                let key = v.address + v.storyboardSpec
                guard key != self.safariStoryboardKey else { return }
                self.safariStoryboardKey = key
                Filmstrip.safari.setImages([], key: key)
                guard !v.storyboardSpec.isEmpty else { return }
                SystemControl.workQueue.async {
                    let r = SafariPlayer.thumbnails(v.storyboardSpec, frameCount: Filmstrip.frameCount)
                    SystemControl.log("safari video: \(r.count) thumbnails")
                    DispatchQueue.main.async { if self.safariStoryboardKey == key { Filmstrip.safari.setImages(r, key: key) } }
                }
            }
        }
    }

    func scrubSafariVideo(_ v: Float, force: Bool = false) {
        guard let s = safariVideo, force || Date().timeIntervalSince(lastScrub) > 0.15 else { return }
        lastScrub = Date()
        let seconds = Double(v) * s.duration
        SystemControl.workQueue.async { SafariPlayer.scrub(seconds) }
    }

    func skipSafariVideo(_ offset: Double) {
        guard let s = safariVideo else { return }
        let seconds = min(s.duration, max(0, s.elapsed + offset))
        safariVideo?.position = Float(seconds / s.duration)
        lastScrub = Date()
        SystemControl.workQueue.async { SafariPlayer.scrub(seconds) }
    }

    func toggleSafariVideo() {
        safariVideo?.isPaused.toggle()
        lastScrub = Date()
        SystemControl.workQueue.async { SafariPlayer.playPause() }
    }

    // MARK: Messages
    /// Tapback: 1 heart, 2 thumbs up, 3 thumbs down, 4 haha, 5 exclamation, 6 question.
    func tapback(_ n: Int) {
        guard let pid = frontApp?.processIdentifier else { return }
        SystemControl.workQueue.async {
            guard AX.pressMenuItem(pid, identifier: "keyCommandTapback:") else { return }
            Thread.sleep(forTimeInterval: 0.35)
            SystemControl.typeText("\(n)")
        }
    }

    // MARK: Safari tabs
    func showTabs() {
        selectedWindow = 1
        panel = .tabs
        refreshTabs()
    }

    func refreshTabs() {
        isLoadingTabs = true
        SystemControl.workQueue.async {
            let result = SafariTab.read()
            let l = result ?? []
            SystemControl.log(result == nil ? "tabs: couldn't reach Safari" : "tabs: \(l.count) tabs")
            DispatchQueue.main.async {
                self.isLoadingTabs = false
                self.isSafariAccessDenied = result == nil
                if l != self.tabs { self.tabs = l }
                if !l.contains(where: { $0.window == self.selectedWindow }) { self.selectedWindow = l.first?.window ?? 1 }
            }
        }
    }

    func refreshTabsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshTabs() }
    }

    func selectTab(_ s: SafariTab) {
        // the chosen window becomes number 1 once it comes to the front
        SystemControl.workQueue.async {
            s.select()
            DispatchQueue.main.async { self.selectedWindow = 1; self.refreshTabs() }
        }
    }

    // MARK: typing suggestions
    /// Only where text is typed: outside Finder, Music and QuickTime, and while app controls are visible.
    func refreshSuggestions() {
        guard showsSuggestions, SystemControl.hasAccessibility, panel == .app, activeBarMode == .app, !isSiriActive,
              !["com.apple.finder", NowPlaying.music, NowPlaying.quickTime, NowPlaying.spotify].contains(frontBundleID)
        else { if suggestions.isActive { suggestions = Suggestions() }; return }
        guard !isReadingSuggestions else { return }
        isReadingSuggestions = true
        SystemControl.workQueue.async {
            let b = TextContext.read()
            DispatchQueue.main.async {
                guard self.showsSuggestions, self.panel == .app, !self.isSiriActive, let b else {
                    self.isReadingSuggestions = false
                    self.lastContext = nil
                    if self.suggestions.isActive { self.suggestions = Suggestions() }
                    return
                }
                guard b != self.lastContext else { self.isReadingSuggestions = false; return }
                self.lastContext = b
                Suggestions.request(b) { o in
                    self.isReadingSuggestions = false
                    if o != self.suggestions { self.suggestions = o }
                }
            }
        }
    }

    private var lastContext: TextContext?

    func selectSuggestion(_ word: String) {
        suggestions.select(word)
        lastContext = nil
    }

    /// The original ">" button: hides/shows suggestions.
    @Published var suggestionsHidden = false

    // MARK: shortcuts
    /// Runs a ⌘ shortcut through the front app's menu first (independent of keyboard layout); falls back to a key press.
    func shortcut(_ keyCode: CGKeyCode, _ flags: CGEventFlags = [], _ character: String? = nil) {
        guard flags.contains(.maskCommand), let character, let pid = frontApp?.processIdentifier else {
            SystemControl.pressKey(keyCode, flags, character: character)
            return
        }
        // the character this key produces in the current layout ("ğ" instead of "[" on Turkish Q)
        let layoutCharacter = InputSource.character(keyCode)
        SystemControl.workQueue.async {
            let shift = flags.contains(.maskShift)
            var found = SystemControl.pressMenuShortcut(pid, character, shift: shift)
            if !found, let layoutCharacter, layoutCharacter.lowercased() != character.lowercased() { found = SystemControl.pressMenuShortcut(pid, layoutCharacter, shift: shift) }
            SystemControl.log("shortcut ⌘\(shift ? "⇧" : "")\(character) (in layout \(layoutCharacter ?? "?")): \(found ? "via menu" : "via key")")
            // not in the menu: send it like a real key press, without forcing the character, whatever the layout produces
            if !found { DispatchQueue.main.async { SystemControl.pressKey(keyCode, flags) } }
        }
    }
}

extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
