import IOKit.ps
import SwiftUI

/// The Dock on the Touch Bar ("Dock" in Touch Bar Shows). Looks come from theme roles: the shelf is the group,
/// the front app `active`, running dots `accent`, badges `danger`.
/// The Dock with whatever the user picked for its right side.
struct DockBar: View {
    @ObservedObject var d: AppState
    @ObservedObject private var s = DockSettings.shared
    var body: some View { WithControlStrip(d: d, showsStrip: s.trailing.showsStrip) { DockRow(d: d) } }
}

struct DockRow: View {
    @ObservedObject var d: AppState
    @ObservedObject private var dock = DockModel.shared
    @ObservedObject private var s = DockSettings.shared
    @StateObject private var drag = DockDrag()
    @Environment(\.theme) private var theme

    var body: some View {
        let items = dock.items(s.content, order: s.order).filter { s.showsFinder || $0.id != "com.apple.finder" }
        let recents = s.recentsShown ? dock.recents.filter { r in !items.contains { $0.id == r.id } } : []
        let style = iconStyle
        let others = s.showsOthers ? dock.others.filter { s.showsTrash || $0.id != "trash" } : []
        HStack(spacing: Metrics.spacing) {
            if s.width >= 1 {
                strip(items, recents, others, style)
            } else {
                GeometryReader { g in
                    strip(items, recents, others, style)
                        .frame(width: g.size.width * max(0.2, s.width))
                        .frame(maxWidth: .infinity, alignment: s.alignment == .center ? .center : s.alignment == .trailing ? .trailing : .leading)
                }
                .frame(height: Metrics.buttonHeight)
            }
            if s.trailing == .nowPlaying, let c = d.nowPlaying { NowPlayingButton(d: d, c: c) }
            if s.trailing.showsStatus && (s.showsBattery || s.showsClock) {
                DockStatus(showsBattery: s.showsBattery, showsClock: s.showsClock).fixedSize().layoutPriority(1)
            }
        }
        .onAppear { dock.setVisible(true) }
        .onDisappear { dock.setVisible(false) }
    }

    private func strip(_ items: [DockApp], _ recents: [DockApp], _ others: [DockApp], _ style: DockIconStyle) -> some View {
        ScrollingStrip(isLocked: { [drag] in drag.id != nil }, fadesEdges: true) {
            Color.clear.frame(width: 2)
            ForEach(items) { a in item(a, style, items: items) }
            if !recents.isEmpty {
                separator(style)
                ForEach(recents) { a in item(a, style, items: nil) }
            }
            if !others.isEmpty {
                separator(style)
                ForEach(others) { a in
                    DockItemView(app: a, style: style, size: iconSize, isFront: false, isRunning: false, isHidden: false, showsDot: false,
                                 badge: nil, spacing: itemSpacing) { openOther(a) }
                }
            }
            Color.clear.frame(width: 2)
        }
        .onPreferenceChange(DockFramesKey.self) { drag.frames = $0 }
        .overlay {
            if items.isEmpty && recents.isEmpty {
                Text(L("No apps")).font(.bar(12)).foregroundStyle(theme.shelfText.opacity(0.5))
            }
        }
        .frame(height: Metrics.buttonHeight)
        .background { if !theme.splitsGroups { GroupBackground() } }
    }

    @ViewBuilder private func separator(_ style: DockIconStyle) -> some View {
        if style == .text {
            Text("|").font(.bar(12)).foregroundStyle(theme.shelfText.opacity(0.4))
        } else {
            Rectangle().fill(theme.shelfText.opacity(0.25)).frame(width: 1, height: 16)
        }
    }

    /// The Trash opens in Finder; a folder opens as a stack on the bar, newest first.
    private func openOther(_ a: DockApp) {
        guard a.id != "trash" else { NSWorkspace.shared.open(a.url); return }
        let files = dock.folderContents(a)
        var l = files.map { u in PopoverItem(text: FileManager.default.displayName(atPath: u.path)) { NSWorkspace.shared.open(u) } }
        l.append(PopoverItem(text: "Open in Finder") { NSWorkspace.shared.open(a.url) })
        d.showPopover(Popover(title: a.name, items: l))
    }

    private var iconStyle: DockIconStyle {
        if s.iconStyle != .auto { return s.iconStyle }
        if let v = theme.widget?.dock?.iconStyle, let st = DockIconStyle(rawValue: v), st != .auto { return st }
        guard theme.isSkin else { return .color }
        switch theme.layer(nil).border {
        case "ascii": return .text
        case "pixel": return .pixel
        default: return .color
        }
    }

    private var itemSpacing: CGFloat { s.spacing.points ?? CGFloat(theme.widget?.dock?.spacing ?? 0) }

    private var iconSize: CGFloat { s.iconSize.points ?? theme.widget?.dock?.iconSize.map { min(24, max(12, CGFloat($0))) } ?? 20 }

    @ViewBuilder private func item(_ a: DockApp, _ style: DockIconStyle, items: [DockApp]?) -> some View {
        let isFront = a.id == d.frontBundleID
        let isRunning = dock.isRunning(a)
        let isLifted = drag.id == a.id
        let badge = s.showsBadges ? dock.badges[a.id] : nil
        DockItemView(app: a, style: style, size: iconSize, isFront: isFront, isRunning: isRunning,
                     isHidden: dock.hidden.contains(a.id), showsDot: s.showsDots && s.content != .running,
                     badge: badge, spacing: itemSpacing, isLaunching: dock.launching.contains(a.id)) {
            release(a, isFront: isFront)
        }
        // the app that comes to the front scrolls into view
        .selectedInStrip(isFront)
        .background(GeometryReader { g in
            Color.clear.preference(key: DockFramesKey.self, value: [a.id: g.frame(in: .named("stripContent"))])
        })
        .scaleEffect(isLifted ? 1.12 : 1)
        .offset(x: isLifted && drag.didMove ? drag.fingerX - (drag.frames[a.id]?.midX ?? drag.fingerX) : 0)
        .zIndex(isLifted ? 2 : 0)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("stripContent")))
            .onChanged { v in
                guard case .second(true, let e) = v else { return }
                if drag.id == nil {
                    withAnimation(.spring(response: 0.25)) { drag.id = a.id }
                    drag.didMove = false
                    drag.startMid = drag.frames[a.id]?.midX ?? 0
                    drag.fingerX = drag.startMid
                }
                // recents stay where the Dock puts them
                guard let e, let items else { return }
                if !drag.didMove {
                    guard abs(e.translation.width) > 9 else { return }
                    drag.didMove = true
                }
                drag.fingerX = drag.startMid + e.translation.width
                move(a, in: items)
            }
            .onEnded { _ in
                guard drag.didMove else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag.id = nil; drag.didMove = false }
            })
    }

    /// The finger came up without sliding away: a tap, or the end of a long press (menu).
    private func release(_ a: DockApp, isFront: Bool) {
        if drag.id == a.id {
            withAnimation(.spring(response: 0.3)) { drag.id = nil }
            if !drag.didMove && s.longPressMenu { d.showPopover(menu(a)) }
            drag.didMove = false
            return
        }
        dock.tap(a, frontID: d.frontBundleID, behavior: s.frontTap)
    }

    private func move(_ a: DockApp, in items: [DockApp]) {
        guard let i = items.firstIndex(of: a) else { return }
        let j = items.filter { $0.id != a.id && (drag.frames[$0.id]?.midX ?? 0) < drag.fingerX }.count
        guard j != i else { return }
        var ids = items.map(\.id)
        ids.remove(at: i)
        ids.insert(a.id, at: j)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { s.order = ids }
    }

    private func menu(_ a: DockApp) -> Popover {
        let app = dock.runningApp(a)
        var l: [PopoverItem] = []
        if let app {
            l.append(PopoverItem(text: "New Window") { dock.newWindow(a) })
            l.append(PopoverItem(text: "Show All Windows") { dock.showWindows(app) })
            l.append(app.isHidden ? PopoverItem(text: "Show") { dock.open(a) } : PopoverItem(text: "Hide") { app.hide() })
        } else {
            l.append(PopoverItem(text: "Open") { dock.open(a) })
        }
        l.append(PopoverItem(text: dock.isPinned(a) ? "Remove from Dock" : "Keep in Dock") { dock.toggleKeepInDock(a) })
        l.append(PopoverItem(text: "Show in Finder") { dock.revealInFinder(a) })
        if let app { l.append(PopoverItem(text: "Quit") { app.terminate() }) }
        return Popover(title: a.name, items: l)
    }
}

struct DockItemView: View {
    let app: DockApp
    let style: DockIconStyle
    let size: CGFloat
    let isFront: Bool
    let isRunning: Bool
    let isHidden: Bool
    let showsDot: Bool
    let badge: String?
    let spacing: CGFloat
    var isLaunching = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        label
            .modifier(Bounce(isOn: isLaunching))
            .frame(width: style == .text ? nil : size + 14)
            .padding(.horizontal, style == .text && !theme.splitsGroups ? 7 : 0)
            .frame(height: Metrics.buttonHeight)
            .modifier(LiquidPress(kind: theme.splitsGroups ? .capsule : .bubble, role: isFront ? .active : nil, isScrollable: true,
                                  isLeadingEnd: true, isTrailingEnd: true, action: action))
            .overlay(alignment: .bottom) { if showsDot && isRunning && style != .text { dot } }
            .overlay(alignment: .topTrailing) { if let badge, style != .text { badgeView(badge) } }
            .padding(.horizontal, spacing / 2)
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .text:
            BarText(verbatim: app.name + (badge != nil ? "*" : ""))
                .opacity(isRunning || !showsDot ? 1 : 0.55)
        case .pixel:
            Image(nsImage: DockIcons.pixelated(app.url)).interpolation(.none).resizable()
                .frame(width: size, height: size).opacity(isHidden ? 0.5 : 1)
        case .mono:
            let tint = theme.isSkin ? theme.layer(isFront ? .active : nil).text : .white
            Image(nsImage: DockIcons.icon(app.url)).resizable().frame(width: size, height: size)
                .saturation(0).colorMultiply(tint).opacity(isHidden ? 0.5 : 1)
        case .color, .auto:
            Image(nsImage: DockIcons.icon(app.url)).resizable().frame(width: size, height: size).opacity(isHidden ? 0.5 : 1)
        }
    }

    private var dot: some View {
        let color: Color = theme.isSkin
            ? (isFront ? theme.layer(.active).text : theme.layer(.accent).fill ?? theme.layer(.accent).text)
            : theme.glassColor(.accent) ?? theme.text.opacity(0.75)
        return Group {
            if style == .pixel { Rectangle().fill(color).frame(width: 3, height: 2) } else { Circle().fill(color).frame(width: 3, height: 3) }
        }
        .offset(y: -0.5)
    }

    @ViewBuilder private func badgeView(_ s: String) -> some View {
        // "3.214" or "3,214" from the Dock
        let digits = s.filter(\.isNumber)
        let isCount = !digits.isEmpty && s.allSatisfy { $0.isNumber || ".,  ".contains($0) }
        let text = isCount ? ((Int(digits) ?? 100) > 99 ? "99+" : digits) : String(s.prefix(3))
        let l = theme.layer(.danger)
        let fill = theme.isSkin ? l.fill : theme.glassColor(.danger)
        let radius = theme.isSkin ? min(l.radius, 5.5) : 5.5
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(theme.isSkin ? l.text : .white)
            .padding(.horizontal, fill == nil ? 0 : 3)
            .frame(minWidth: 11, minHeight: 11)
            .background { if let fill { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill) } }
            .offset(x: -1, y: -1)
            .allowsHitTesting(false)
    }
}

/// Battery and clock on the right, read once a minute and when the charger changes.
struct DockStatus: View {
    var showsBattery = true
    var showsClock = true
    @ObservedObject private var power = PowerWatch.shared
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { t in
            HStack(spacing: 4) {
                if showsBattery, let b = Battery.read() {
                    HStack(spacing: 1) {
                        if Battery.isLowPower { Icon(b.symbol).foregroundStyle(Battery.lowPowerColor) } else { Icon(b.symbol) }
                        BarText(verbatim: "\(b.percent)%", tabular: true)
                    }
                }
                if showsClock { BarText(verbatim: t.date.formatted(.dateTime.hour().minute()), tabular: true) }
            }
            .font(.bar(12))
            .foregroundStyle(theme.shelfText)
            .padding(.horizontal, 8)
            .frame(height: Metrics.buttonHeight)
            .background { if !theme.splitsGroups { GroupBackground() } }
        }
        .onAppear { power.setVisible(true) }
        .onDisappear { power.setVisible(false) }
    }
}

enum Battery {
    /// Low Power Mode's yellow, the same in every theme like the system's own battery
    static let lowPowerColor = Color(hex: 0xFFD60A)
    static var isLowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// nil on Macs without a battery
    static func read() -> (percent: Int, symbol: String, isCharging: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let p = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  p[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = p[kIOPSCurrentCapacityKey] as? Int, let max = p[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let percent = now * 100 / max
            // "is charging" turns true seconds after the plug goes in, and stays false at 100%: the power source is known at once
            if p[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue { return (percent, "battery.100.bolt", true) }
            let level = [0, 25, 50, 75, 100].min { abs($0 - percent) < abs($1 - percent) }!
            return (percent, "battery.\(level)", false)
        }
        return nil
    }
}

/// Tells when the charger is plugged in or pulled, so the battery doesn't wait for its next timed read.
final class PowerWatch: ObservableObject {
    static let shared = PowerWatch()
    /// for the widgets, which keep their own copy of the battery
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?
    private var visibleCount = 0

    private init() {
        // Low Power Mode; posted on any thread
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.changed() }
    }

    private func changed() {
        guard visibleCount > 0 else { return }
        objectWillChange.send()
        onChange?()
    }

    func setVisible(_ isVisible: Bool) {
        visibleCount = max(0, visibleCount + (isVisible ? 1 : -1))
        if visibleCount > 0, source == nil {
            source = IOPSNotificationCreateRunLoopSource({ _ in
                PowerWatch.shared.changed()
                // the charge and the rest settle a moment after the plug
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { PowerWatch.shared.changed() }
            }, nil)?.takeRetainedValue()
            if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        } else if visibleCount == 0, let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes)
            source = nil
        }
    }
}

/// The Dock's launch bounce, as far as 30 pt of height allow.
private struct Bounce: ViewModifier {
    let isOn: Bool
    @StateObject private var k = BounceState()

    func body(content: Content) -> some View {
        content
            .offset(y: k.isUp ? -4 : 0)
            .onAppear { set(isOn) }
            .onChange(of: isOn) { _, on in set(on) }
    }

    private func set(_ on: Bool) {
        if on {
            withAnimation(.easeOut(duration: 0.3).repeatForever(autoreverses: true)) { k.isUp = true }
        } else if k.isUp {
            withAnimation(.easeOut(duration: 0.2)) { k.isUp = false }
        }
    }
}

private final class BounceState: ObservableObject { @Published var isUp = false }

final class DockDrag: ObservableObject {
    /// the item lifted by a long press
    @Published var id: String?
    @Published var fingerX: CGFloat = 0
    var didMove = false
    var startMid: CGFloat = 0
    var frames: [String: CGRect] = [:]
}

struct DockFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
