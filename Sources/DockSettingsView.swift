import AppKit
import SwiftUI

/// The small "Dock Settings…" window: a preset and a handful of switches. Built when opened, let go when closed.
enum DockSettingsWindow {
    private static var window: NSWindow?
    private static var delegate: CloseDelegate?

    static func open(_ d: AppState) {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Dock Settings")
        w.contentView = NSHostingView(rootView: DockSettingsView(d: d))
        w.isReleasedWhenClosed = false
        w.center()
        delegate = CloseDelegate { window = nil; delegate = nil }
        w.delegate = delegate
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ n: Notification) { onClose() }
    }
}

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
            Toggle(L("Recent apps after a separator"), isOn: Binding(get: { s.recentsShown }, set: { s.showsRecents = $0 }))
            Toggle(L("Folders and Trash after a separator"), isOn: $s.showsOthers)
            Toggle(L("Battery and clock on the right"), isOn: $s.showsStatus)
            Toggle(L("Badges"), isOn: $s.showsBadges)
            Toggle(L("Dots under running apps"), isOn: $s.showsDots)
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
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
