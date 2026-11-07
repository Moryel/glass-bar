import AppKit
import SwiftUI

// Built-in widgets. A widget only says what to show (an icon, a value, a state); GlassButton and the theme decide
// how it looks, so the same battery is a glass capsule, [bat 87%] or a pixel key. States map to roles.
// Nothing is read until a widget is on the bar, and the timer stops when the last one goes away.

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, battery, cpu, memory, worldClock, clipboard, nowPlaying, dock

    var id: String { rawValue }

    var name: String {
        switch self {
        case .clock: L("Clock")
        case .battery: L("Battery")
        case .cpu: L("CPU")
        case .memory: L("Memory")
        case .worldClock: L("World Clock")
        case .clipboard: L("Clipboard")
        case .nowPlaying: L("Now Playing")
        case .dock: L("Dock")
        }
    }

    var summary: String {
        switch self {
        case .clock: L("The time. Tap for Notification Center.")
        case .battery: L("Charge and charging state. Low battery uses the warning role.")
        case .cpu: L("CPU load, every 2 seconds. Tap for Activity Monitor.")
        case .memory: L("Memory in use. Tap for Activity Monitor.")
        case .worldClock: L("The time in another city.")
        case .clipboard: L("The last text you copied. Tap to paste it.")
        case .nowPlaying: L("The song that is playing, while something plays.")
        case .dock: L("Your Dock. Shown as a bar of its own or inside a layout.")
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .battery: "battery.75"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .worldClock: "globe"
        case .clipboard: "doc.on.clipboard"
        case .nowPlaying: "music.note"
        case .dock: "dock.rectangle"
        }
    }

    /// shown instead of the icon in themes with ASCII brackets
    var shortName: String {
        switch self {
        case .clock: "time"
        case .battery: "bat"
        case .cpu: "cpu"
        case .memory: "mem"
        case .worldClock: "tz"
        case .clipboard: "clip"
        case .nowPlaying: "play"
        case .dock: "dock"
        }
    }

    /// widgets that can sit next to the Control Strip
    static let stripKinds: [WidgetKind] = [.clock, .battery, .cpu, .memory, .worldClock, .clipboard, .nowPlaying]
}

/// The values behind the widgets, read on one shared timer while any widget is visible.
final class WidgetData: ObservableObject {
    static let shared = WidgetData()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var battery = Battery.read()
    @Published private(set) var clipboard: String?

    private var timer: Timer?
    private var visibleCount = 0
    private var ticks = 0
    private var lastCPU: (busy: UInt64, total: UInt64)?
    private var clipboardCount = -1

    func setVisible(_ isVisible: Bool) {
        visibleCount = max(0, visibleCount + (isVisible ? 1 : -1))
        if visibleCount > 0, timer == nil {
            ticks = 0
            refresh()
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if visibleCount == 0 {
            timer?.invalidate()
            timer = nil
            lastCPU = nil
        }
    }

    private func refresh() {
        readCPU()
        readMemory()
        if ticks % 15 == 0 { battery = Battery.read() }
        let pb = NSPasteboard.general
        if pb.changeCount != clipboardCount {
            clipboardCount = pb.changeCount
            clipboard = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        ticks += 1
    }

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3), total = busy + UInt64(t.2)
        if let last = lastCPU, total > last.total {
            let v = Double(busy - last.busy) / Double(total - last.total)
            if abs(v - cpu) > 0.005 { cpu = v }
        }
        lastCPU = (busy, total)
    }

    private func readMemory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let pages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        let used = Double(pages * UInt64(vm_kernel_page_size))
        if abs(used - memoryUsed) > 50_000_000 { memoryUsed = used }
    }
}

/// Which widgets sit next to the Control Strip, and the world clock's city.
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    /// built-in kinds by name, script widgets as "script:<id>"
    @Published var strip = Defaults.stringArray("barWidgets") ?? [] { didSet { Defaults.set("barWidgets", strip) } }
    @Published var worldClockZone = Defaults.string("worldClockZone").nilIfEmpty ?? "Europe/London" {
        didSet { Defaults.set("worldClockZone", worldClockZone) }
    }

    func toggle(_ k: String) {
        if let i = strip.firstIndex(of: k) { strip.remove(at: i) } else { strip.append(k) }
    }

    func move(_ k: String, by step: Int) {
        guard let i = strip.firstIndex(of: k) else { return }
        let j = min(max(0, i + step), strip.count - 1)
        strip.swapAt(i, j)
    }

    static let zones = ["America/Los_Angeles", "America/Chicago", "America/New_York", "America/Sao_Paulo", "Europe/London", "Europe/Berlin",
                        "Europe/Istanbul", "Europe/Moscow", "Asia/Dubai", "Asia/Kolkata", "Asia/Shanghai", "Asia/Tokyo", "Australia/Sydney",
                        "Pacific/Auckland", "UTC"]

    static func city(_ zone: String) -> String {
        zone == "UTC" ? "UTC" : (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The widgets chosen in the Hub, left of the Control Strip.
struct WidgetStrip: View {
    @ObservedObject var d: AppState
    @ObservedObject private var s = WidgetSettings.shared

    var body: some View {
        if !s.strip.isEmpty {
            HStack(spacing: Metrics.spacing) {
                ForEach(s.strip, id: \.self) { AnyWidgetView(d: d, id: $0) }
            }
            .fixedSize()
        }
    }
}

/// One widget. `option` is a city's time zone for the world clock.
struct WidgetView: View {
    @ObservedObject var d: AppState
    let kind: WidgetKind
    var option: String? = nil
    @ObservedObject private var data = WidgetData.shared
    @ObservedObject private var settings = WidgetSettings.shared
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch kind {
            case .clock:
                TimelineView(.everyMinute) { t in
                    capsule(value: t.date.formatted(.dateTime.hour().minute()), role: nil, action: SystemControl.openNotificationCenter)
                }
            case .worldClock:
                let zone = option ?? settings.worldClockZone
                TimelineView(.everyMinute) { t in
                    capsule(value: WidgetSettings.city(zone) + " " + time(t.date, zone), role: nil, showsIcon: false) {}
                }
            case .battery:
                if let b = data.battery {
                    capsule(value: "\(b.percent)%", role: b.isCharging ? .success : b.percent <= 20 ? .warning : nil, symbol: b.symbol,
                            action: { open("x-apple.systempreferences:com.apple.Battery-Settings.extension") })
                }
            case .cpu:
                capsule(value: "\(Int((data.cpu * 100).rounded()))%", role: data.cpu > 0.8 ? .warning : nil, action: activityMonitor)
            case .memory:
                let gb = data.memoryUsed / 1_073_741_824
                capsule(value: String(format: "%.1f GB", gb), role: data.memoryUsed / data.memoryTotal > 0.9 ? .warning : nil, action: activityMonitor)
            case .clipboard:
                if let c = data.clipboard, !c.isEmpty {
                    capsule(value: c.count > 18 ? String(c.prefix(17)) + "…" : c, role: nil) { d.shortcut(9, .maskCommand, "v") }
                }
            case .nowPlaying:
                if let c = d.nowPlaying { NowPlayingButton(d: d, c: c) }
            case .dock:
                DockRow(d: d)
            }
        }
        .onAppear { if kind.readsData { data.setVisible(true) } }
        .onDisappear { if kind.readsData { data.setVisible(false) } }
    }

    private func capsule(value: String, role: Role?, symbol: String? = nil, showsIcon: Bool = true, action: @escaping () -> Void) -> some View {
        let look = theme.widget?.looks[kind.rawValue]
        let isASCII = theme.isSkin && theme.layer(nil).border == "ascii"
        return GlassButton(width: nil, highlight: Role.named(look?.role) ?? role, action: action) {
            HStack(spacing: 4) {
                if let label = look?.label ?? (isASCII ? kind.shortName : nil) {
                    BarText(verbatim: label)
                } else if showsIcon {
                    Icon(look?.icon ?? symbol ?? kind.symbol)
                }
                BarText(verbatim: value, tabular: true)
            }
        }
    }

    private func time(_ date: Date, _ zone: String) -> String {
        var f = Date.FormatStyle.dateTime.hour().minute()
        f.timeZone = TimeZone(identifier: zone) ?? .current
        return date.formatted(f)
    }

    private func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    private func activityMonitor() {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: u, configuration: .init())
        }
    }
}

private extension WidgetKind {
    var readsData: Bool { [.battery, .cpu, .memory, .clipboard].contains(self) }
}

extension Role {
    /// "active" → .active; nil for unknown names
    static func named(_ s: String?) -> Role? {
        switch s {
        case "active": .active
        case "primary": .primary
        case "accent": .accent
        case "operator": .operatorKey
        case "suggestions": .suggestions
        case "danger": .danger
        case "warning": .warning
        case "success": .success
        default: nil
        }
    }
}

// MARK: Hub page

/// The Widgets tab: every built-in widget drawn with the current theme, and which ones sit on the bar.
struct WidgetsPage: View {
    @ObservedObject var m: HubModel
    @ObservedObject private var s = WidgetSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Widgets show a value and leave the look to your theme. Pick the ones you want left of the Control Strip, or add them to a layout."))
                    .foregroundStyle(.secondary)
                if !s.strip.isEmpty { onTheBar }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(WidgetKind.allCases) { card($0) }
                }
                ScriptWidgetsSection(m: m)
            }
            .padding(24)
        }
    }

    private var onTheBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("On the Bar")).font(.headline)
            HStack(spacing: 8) {
                ForEach(s.strip, id: \.self) { k in
                    HStack(spacing: 4) {
                        Button { s.move(k, by: -1) } label: { Image(systemName: "chevron.left") }.disabled(s.strip.first == k)
                        Text(WidgetKind(rawValue: k)?.name ?? ScriptWidgetStore.shared.widget(String(k.dropFirst(7)))?.name ?? k)
                        Button { s.move(k, by: 1) } label: { Image(systemName: "chevron.right") }.disabled(s.strip.last == k)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }
        }
    }

    private func card(_ k: WidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(k.name, systemImage: k.symbol).font(.headline)
                Spacer()
                if WidgetKind.stripKinds.contains(k) {
                    Toggle(L("On the Bar"), isOn: Binding(get: { s.strip.contains(k.rawValue) }, set: { _ in s.toggle(k.rawValue) }))
                        .toggleStyle(.switch).labelsHidden()
                } else {
                    Button(L("Dock Settings…")) { m.page = .dock }
                }
            }
            Text(k.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            preview(k)
            if k == .worldClock {
                Picker(L("City"), selection: $s.worldClockZone) {
                    ForEach(WidgetSettings.zones, id: \.self) { Text(WidgetSettings.city($0)).tag($0) }
                }
            }
            Text(verbatim: "{ \"type\": \"widget\", \"widget\": \"\(k.rawValue)\" }")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private func preview(_ k: WidgetKind) -> some View {
        let t = m.d.theme
        return HStack {
            if k == .dock {
                Text(L("Shown as its own bar: Touch Bar Shows → Dock")).font(.caption).foregroundStyle(.white.opacity(0.6))
            } else if k == .nowPlaying && m.d.nowPlaying == nil {
                Text(L("Appears while something plays")).font(.caption).foregroundStyle(.white.opacity(0.6))
            } else {
                WidgetView(d: m.d, kind: k)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.barHeight)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if let b = t.skin?.bar { SkinBarBackground(style: b, theme: t) } else { Color.black }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .environment(\.theme, t)
        .font(t.font(14))
        .textCase(t.letterCase)
    }
}
