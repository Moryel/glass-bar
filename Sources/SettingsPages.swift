import AppKit
import ServiceManagement
import SwiftUI

// The menu bar settings as Hub pages. Both write the same AppState properties, so either place stays in sync.

struct GeneralSettingsView: View {
    @ObservedObject var d: AppState
    @AppStorage("themeSounds") private var themeSounds = false
    @AppStorage("siriStyle") private var siriStyle = SiriStyle.liquid
    @AppStorage("siriBrightness") private var siriBrightness = 1.0
    @AppStorage("siriFringe") private var siriFringe = 1.0
    @AppStorage("siriThinkingDots") private var siriThinkingDots = true

    var body: some View {
        Form {
            Section(L("Touch Bar")) {
                Picker(L("Touch Bar Shows"), selection: Binding(get: { d.barMode }, set: { d.barMode = $0; d.panel = .app })) {
                    ForEach(BarMode.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Picker(L("Press and Hold fn Key to Show"), selection: $d.fnBarMode) {
                    ForEach(BarMode.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Toggle(L("esc Key on the Bar"), isOn: $d.showsEsc)
                Toggle(L("Show Typing Suggestions"), isOn: $d.showsSuggestions)
            }
            Section(L("Look")) {
                Picker(L("Theme"), selection: Binding(get: { d.theme.id }, set: { id in ThemeStore.shared.theme(id: id).map(d.apply) })) {
                    ForEach(ThemeStore.shared.all, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                Toggle(L("Play Theme Sounds"), isOn: $themeSounds)
                Picker(L("Background"), selection: Binding(get: { d.backdrop }, set: { a in
                    if a == .customImage { d.chooseBackdropImage() } else { d.backdrop = a }
                })) {
                    ForEach(Backdrop.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Picker(L("Color Temperature"), selection: $d.colorTemperature) {
                    ForEach(ColorTemperature.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            }
            Section(L("Siri")) {
                Picker(L("Siri Animation"), selection: $siriStyle) {
                    ForEach(SiriStyle.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                if siriStyle == .liquid {
                    Slider(value: $siriBrightness, in: 0.5...1.5) { Text(L("Brightness")) }
                    Slider(value: $siriFringe, in: 0...2.5) { Text(L("Colored Edges")) }
                    Toggle(L("Dots While Thinking"), isOn: $siriThinkingDots)
                }
            }
            Section {
                Toggle(L("Open at Login"), isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    d.objectWillChange.send()
                }))
            }
        }
        .formStyle(.grouped)
    }
}

struct ControlStripSettingsView: View {
    @ObservedObject var d: AppState

    var body: some View {
        Form {
            Section {
                Toggle(L("Show Control Strip"), isOn: $d.showsControlStrip)
                HStack {
                    Text(L("Drag to reorder right on the Touch Bar."))
                    Spacer()
                    Button(L("Customize Control Strip…")) { d.panel = .app; d.isEditingControlStrip = true }
                }
            }
            Section(String(format: L("Control Strip Buttons (up to %d)"), StripButton.maxCount)) {
                ForEach(StripButton.allCases, id: \.self) { t in
                    Toggle(isOn: Binding(get: { d.stripButtons.contains(t) }, set: { _ in d.toggleStripButton(t) })) {
                        Label(t.name, systemImage: t.symbol)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension AppState {
    func chooseBackdropImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = L("Choose an image to show behind the Touch Bar")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        backdropImagePath = url.path
        backdrop = .customImage
    }

    /// The chosen button is appended; past the limit the oldest one is removed.
    func toggleStripButton(_ t: StripButton) {
        var l = stripButtons
        if let i = l.firstIndex(of: t) { l.remove(at: i) } else { l.append(t); if l.count > StripButton.maxCount { l.removeFirst() } }
        stripButtons = l
    }
}
