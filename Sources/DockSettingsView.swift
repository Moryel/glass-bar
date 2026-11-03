import SwiftUI

/// The Dock page in the Hub's Settings.
struct DockSettingsView: View {
    @ObservedObject var d: AppState
    @ObservedObject private var s = DockSettings.shared

    var body: some View {
        Form {
            if d.barMode != .dock {
                HStack {
                    Text(L("The Dock shows when Touch Bar Shows is set to Dock."))
                    Spacer()
                    Button(L("Show Dock")) { d.barMode = .dock; d.panel = .app }
                }
            }
            Picker(L("Preset"), selection: Binding(get: { s.preset }, set: { if let p = $0 { s.apply(p) } })) {
                ForEach(DockPreset.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
                if s.preset == nil { Text(L("Custom")).tag(DockPreset?.none) }
            }
            Section(L("Items")) {
                Toggle(L("Finder"), isOn: $s.showsFinder)
                Toggle(L("Recent apps after a separator"), isOn: Binding(get: { s.recentsShown }, set: { s.showsRecents = $0 }))
                Toggle(L("Folders and Trash after a separator"), isOn: $s.showsOthers)
                if s.showsOthers { Toggle(L("Trash"), isOn: $s.showsTrash) }
                Toggle(L("Badges"), isOn: $s.showsBadges)
                Toggle(L("Dots under running apps"), isOn: $s.showsDots)
            }
            Section(L("Size")) {
                LabeledContent(L("Width")) {
                    HStack {
                        Slider(value: $s.width, in: 0.3...1, step: 0.05)
                        Text(s.width >= 1 ? L("Full") : "\(Int((s.width * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                if s.width < 1 {
                    Picker(L("Position"), selection: $s.alignment) {
                        Text(L("Left")).tag(DockAlignment.leading)
                        Text(L("Center")).tag(DockAlignment.center)
                        Text(L("Right")).tag(DockAlignment.trailing)
                    }
                    .pickerStyle(.segmented)
                }
                Picker(L("Spacing"), selection: $s.spacing) {
                    Text(L("Theme default")).tag(DockSpacing.auto)
                    Text(L("Tight")).tag(DockSpacing.tight)
                    Text(L("Normal")).tag(DockSpacing.normal)
                    Text(L("Wide")).tag(DockSpacing.wide)
                }
                Picker(L("Icon size"), selection: $s.iconSize) {
                    Text(L("Theme default")).tag(DockIconSize.auto)
                    Text(L("Small")).tag(DockIconSize.small)
                    Text(L("Medium")).tag(DockIconSize.medium)
                    Text(L("Large")).tag(DockIconSize.large)
                }
                Picker(L("Icons"), selection: $s.iconStyle) {
                    Text(L("Theme default")).tag(DockIconStyle.auto)
                    Text(L("Color")).tag(DockIconStyle.color)
                    Text(L("Monochrome")).tag(DockIconStyle.mono)
                    Text(L("Names")).tag(DockIconStyle.text)
                    Text(L("Pixel")).tag(DockIconStyle.pixel)
                }
            }
            Section(L("Right Side")) {
                Picker(L("Shows"), selection: $s.trailing) {
                    Text(L("Control Strip")).tag(DockTrailing.controlStrip)
                    Text(L("Status and Control Strip")).tag(DockTrailing.statusAndStrip)
                    Text(L("Status only")).tag(DockTrailing.status)
                    Text(L("Now Playing and Status")).tag(DockTrailing.nowPlaying)
                    Text(L("Nothing")).tag(DockTrailing.nothing)
                }
                if s.trailing.showsStatus {
                    Toggle(L("Battery"), isOn: $s.showsBattery)
                    Toggle(L("Clock"), isOn: $s.showsClock)
                }
            }
            Section(L("Touch")) {
                Picker(L("Tap on the app in front"), selection: $s.frontTap) {
                    Text(L("Hides it")).tag(DockFrontTap.hide)
                    Text(L("Shows its windows")).tag(DockFrontTap.windows)
                    Text(L("Does nothing")).tag(DockFrontTap.nothing)
                }
                Toggle(L("Long press opens the app menu"), isOn: $s.longPressMenu)
                HStack {
                    Text(L("Press and hold an icon, then slide to move it.")).foregroundStyle(.secondary)
                    Spacer()
                    if !s.order.isEmpty { Button(L("Use Dock Order")) { s.order = [] } }
                }
            }
        }
        .formStyle(.grouped)
    }
}
