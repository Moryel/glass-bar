import AppKit
import JavaScriptCore
import SwiftUI

// Script widgets: a folder with widget.json and a JavaScript file, run in JavaScriptCore (no WebView, no files,
// no network unless the widget asks for it). A script only runs while its widget is on the bar, on its own queue,
// with a time limit per call so a stuck loop can't hold the CPU.

struct ScriptWidgetInfo: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var author: String? = nil
    var version: Int? = nil
    var description: String? = nil
    var script: String? = nil
    /// seconds between update() calls, at least 1
    var refresh: Double? = nil
    /// network, openLinks, keys
    var permissions: [String]? = nil
    var baseURL: URL? = nil

    enum CodingKeys: String, CodingKey { case id, name, author, version, description, script, refresh, permissions }

    func allows(_ p: String) -> Bool { permissions?.contains(p) ?? false }

    static let permissionNames = ["network": "Use the internet", "openLinks": "Open links and apps", "keys": "Press keyboard shortcuts"]
}

final class ScriptWidgetStore {
    static let shared = ScriptWidgetStore()
    let folder = Edition.supportFolder.appendingPathComponent("Widgets", isDirectory: true)
    private(set) var all: [ScriptWidgetInfo] = []

    private init() { reload() }

    func reload() {
        let l = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        all = l.compactMap { try? Self.load($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func widget(_ id: String) -> ScriptWidgetInfo? { all.first { $0.id == id } }

    static func load(_ url: URL) throws -> ScriptWidgetInfo {
        var w = try JSONDecoder().decode(ScriptWidgetInfo.self, from: Data(contentsOf: url.appendingPathComponent("widget.json")))
        // the id becomes a folder name on install; "../x" would copy (and first delete) outside Widgets
        guard isSafeID(w.id) else { throw CocoaError(.fileReadCorruptFile) }
        w.baseURL = url
        if let p = w.permissions?.filter({ ScriptWidgetInfo.permissionNames[$0] == nil }), !p.isEmpty {
            SystemControl.log("widget \(w.id): unknown permissions \(p), ignored")
            w.permissions = w.permissions?.filter { ScriptWidgetInfo.permissionNames[$0] != nil }
        }
        return w
    }

    @discardableResult func install(_ url: URL) throws -> ScriptWidgetInfo {
        let w = try Self.load(url)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let to = folder.appendingPathComponent(w.id, isDirectory: true)
        if to.standardizedFileURL != url.standardizedFileURL {
            try? fm.removeItem(at: to)
            try fm.copyItem(at: url, to: to)
        }
        reload()
        return w
    }

    func delete(_ id: String) {
        if let u = widget(id)?.baseURL { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        reload()
    }

    /// A small example to start from, opened in Finder.
    func createSample() throws -> URL {
        let fm = FileManager.default
        var n = 1
        var to = folder.appendingPathComponent("my-widget", isDirectory: true)
        while fm.fileExists(atPath: to.path) { n += 1; to = folder.appendingPathComponent("my-widget-\(n)", isDirectory: true) }
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        let id = to.lastPathComponent
        let json = """
        {
          "id": "\(id)",
          "name": "My Widget",
          "author": "\(NSFullUserName())",
          "version": 1,
          "description": "Days left in the year. Tap to count.",
          "script": "main.js",
          "refresh": 60,
          "permissions": []
        }

        """
        let js = """
        // update() runs when the widget appears and then every "refresh" seconds; tap() runs when it's tapped.
        // glassbar.show({ text, icon, role }) is all a widget needs. See docs/WIDGETS.md for the rest.
        let taps = Number(glassbar.store.get("taps") || 0)

        function update() {
          const now = new Date()
          const days = Math.ceil((new Date(now.getFullYear() + 1, 0, 1) - now) / 86400000)
          glassbar.show({ text: days + "d · " + taps, icon: "calendar" })
        }

        function tap() {
          taps += 1
          glassbar.store.set("taps", String(taps))
          update()
        }

        """
        try json.write(to: to.appendingPathComponent("widget.json"), atomically: true, encoding: .utf8)
        try js.write(to: to.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        reload()
        return to
    }
}

/// Runs one widget's script while it's visible. One runner per widget, however many places show it.
final class ScriptRunner: ObservableObject {
    private static var runners: [String: ScriptRunner] = [:]

    static func shared(_ info: ScriptWidgetInfo, _ d: AppState) -> ScriptRunner {
        if let r = runners[info.id], r.info == info { return r }
        let r = ScriptRunner(info, d)
        runners[info.id] = r
        return r
    }

    private var visibleCount = 0

    func setVisible(_ isVisible: Bool) {
        visibleCount = max(0, visibleCount + (isVisible ? 1 : -1))
        if visibleCount == 1 && isVisible { start() } else if visibleCount == 0 { stop() }
    }

    @Published var text = ""
    @Published var icon: String?
    @Published var role: String?

    let info: ScriptWidgetInfo
    weak var d: AppState?
    private let queue: DispatchQueue
    private var context: JSContext?
    private var timer: DispatchSourceTimer?

    private init(_ info: ScriptWidgetInfo, _ d: AppState) {
        self.info = info
        self.d = d
        queue = DispatchQueue(label: "widget.\(info.id)", qos: .utility)
    }

    private func start() {
        queue.async { [weak self] in
            guard let self, self.context == nil else { return }
            guard let base = self.info.baseURL, let file = packageFile(base, self.info.script ?? "main.js"),
                  let source = try? String(contentsOf: file, encoding: .utf8)
            else { self.publish(text: "?", icon: nil, role: "danger"); return }
            guard let c = self.makeContext() else {
                SystemControl.log("widget \(self.info.id): no time limit on this macOS, not run")
                self.publish(text: "?", icon: "exclamationmark.triangle", role: "danger"); return
            }
            c.evaluateScript(source, withSourceURL: file)
            self.context = c
            self.call("update")
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            let every = max(1, self.info.refresh ?? 60)
            t.schedule(deadline: .now() + every, repeating: every, leeway: .milliseconds(Int(every * 200)))
            t.setEventHandler { [weak self] in self?.call("update") }
            t.resume()
            self.timer = t
        }
    }

    private func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.context = nil
        }
    }

    func tap() { queue.async { [weak self] in self?.call("tap") } }

    /// A call that runs into the time limit stops the widget for good (until it's shown again).
    private func call(_ name: String) {
        guard let c = context, let f = c.objectForKeyedSubscript(name), !f.isUndefined else { return }
        let start = DispatchTime.now()
        f.call(withArguments: [])
        guard Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9 >= ScriptRunner.limit * 0.9 else { return }
        SystemControl.log("widget \(info.id): \(name)() took too long, stopped")
        timer?.cancel()
        timer = nil
        context = nil
        publish(text: L("stopped"), icon: "exclamationmark.triangle", role: "danger")
    }

    static let limit = 0.5

    private func publish(text: String, icon: String?, role: String?) {
        DispatchQueue.main.async {
            if self.text != text { self.text = text }
            if self.icon != icon { self.icon = icon }
            if self.role != role { self.role = role }
        }
    }

    private func makeContext() -> JSContext? {
        let c = JSContext()!
        guard ScriptRunner.limitTime(c, seconds: ScriptRunner.limit) else { return nil }
        let id = info.id
        c.exceptionHandler = { _, e in SystemControl.log("widget \(id): \(e?.toString() ?? "error")") }
        let api = JSValue(newObjectIn: c)!
        let show: @convention(block) (JSValue) -> Void = { [weak self] v in
            let s = { (k: String) -> String? in
                let x = v.objectForKeyedSubscript(k)
                return x == nil || x!.isUndefined || x!.isNull ? nil : x!.toString()
            }
            self?.publish(text: s("text") ?? "", icon: s("icon"), role: s("role"))
        }
        let log: @convention(block) (String) -> Void = { SystemControl.log("widget \(id): \($0)") }
        let fetch: @convention(block) (String, JSValue) -> Void = { [weak self] s, callback in
            guard let self else { return }
            guard self.info.allows("network") else { SystemControl.log("widget \(id): fetch needs the network permission"); return }
            guard let u = URL(string: s), ScriptRunner.isPublicWeb(u) else { SystemControl.log("widget \(id): fetch only goes to https web addresses"); return }
            guard !self.isFetching else { return }
            self.isFetching = true
            var r = URLRequest(url: u, timeoutInterval: 10)
            r.httpShouldHandleCookies = false
            ScriptRunner.session.dataTask(with: r) { data, _, _ in
                // a megabyte is plenty for a widget; bigger answers are dropped
                let text = data.flatMap { $0.count <= 1_000_000 ? String(data: $0, encoding: .utf8) : nil }
                self.queue.async { self.isFetching = false; _ = callback.call(withArguments: [text ?? NSNull()]) }
            }.resume()
        }
        let open: @convention(block) (String) -> Void = { [weak self] s in
            guard self?.info.allows("openLinks") == true else { SystemControl.log("widget \(id): open needs the openLinks permission"); return }
            DispatchQueue.main.async { self?.d?.run(LayoutAction(open: s)) }
        }
        let key: @convention(block) (String) -> Void = { [weak self] s in
            guard self?.info.allows("keys") == true else { SystemControl.log("widget \(id): key needs the keys permission"); return }
            DispatchQueue.main.async { self?.d?.run(LayoutAction(shortcut: s)) }
        }
        let storeKey = "scriptWidget." + id
        let get: @convention(block) (String) -> Any = { k in (UserDefaults.standard.dictionary(forKey: storeKey)?[k] as? String) ?? NSNull() }
        let set: @convention(block) (String, String) -> Void = { k, v in
            var dict = UserDefaults.standard.dictionary(forKey: storeKey) ?? [:]
            guard dict.count < 50 || dict[k] != nil, v.count < 2000 else { return }
            dict[k] = v
            UserDefaults.standard.set(dict, forKey: storeKey)
        }
        let store = JSValue(newObjectIn: c)!
        store.setObject(get, forKeyedSubscript: "get" as NSString)
        store.setObject(set, forKeyedSubscript: "set" as NSString)
        api.setObject(show, forKeyedSubscript: "show" as NSString)
        api.setObject(log, forKeyedSubscript: "log" as NSString)
        api.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        api.setObject(open, forKeyedSubscript: "open" as NSString)
        api.setObject(key, forKeyedSubscript: "key" as NSString)
        api.setObject(store, forKeyedSubscript: "store" as NSString)
        c.setObject(api, forKeyedSubscript: "glassbar" as NSString)
        return c
    }

    /// JSContextGroupSetExecutionTimeLimit isn't in the public headers; without it a stuck loop could spin forever,
    /// so scripts don't run at all then.
    private static func limitTime(_ c: JSContext, seconds: Double) -> Bool {
        typealias SetLimit = @convention(c) (JSContextGroupRef, Double, OpaquePointer?, UnsafeMutableRawPointer?) -> Void
        guard let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else { return false }
        unsafeBitCast(f, to: SetLimit.self)(JSContextGetGroup(c.jsGlobalContextRef), seconds, nil, nil)
        return true
    }

    private var isFetching = false

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// https on a public host: no localhost, no home network (router pages, printers), no ports or user names.
    static func isPublicWeb(_ u: URL) -> Bool {
        guard u.scheme?.lowercased() == "https", u.user == nil, u.port == nil, let h = u.host?.lowercased(), h.contains(".") else { return false }
        if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost") || h.hasSuffix(".internal") || h.contains(":") { return false }
        let n = h.split(separator: ".").compactMap { Int($0) }
        if n.count == 4 {
            // any bare IPv4: private ranges are the risk, and public services have names
            return false
        }
        return true
    }
}

/// A script widget on the bar, drawn like any other widget.
struct ScriptWidgetView: View {
    @ObservedObject private var r: ScriptRunner

    init(info: ScriptWidgetInfo, d: AppState) { r = ScriptRunner.shared(info, d) }

    var body: some View {
        GlassButton(width: nil, highlight: Role.named(r.role), action: r.tap) {
            HStack(spacing: 4) {
                if let i = r.icon { Icon(i) }
                BarText(verbatim: r.text.isEmpty ? "…" : r.text).lineLimit(1)
            }
        }
        .onAppear { r.setVisible(true) }
        .onDisappear { r.setVisible(false) }
    }
}

/// A widget by id: a built-in kind, or "script:<id>".
struct AnyWidgetView: View {
    @ObservedObject var d: AppState
    let id: String
    var option: String? = nil

    var body: some View {
        if let k = WidgetKind(rawValue: id) {
            WidgetView(d: d, kind: k, option: option)
        } else if id.hasPrefix("script:"), let w = ScriptWidgetStore.shared.widget(String(id.dropFirst(7))) {
            ScriptWidgetView(info: w, d: d)
        }
    }
}

// MARK: Hub

/// The script widget part of the Widgets page: installed widgets with what they may do, install and remove.
struct ScriptWidgetsSection: View {
    @ObservedObject var m: HubModel
    @ObservedObject private var s = WidgetSettings.shared
    @StateObject private var state = ScriptSectionState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Script Widgets")).font(.headline)
                Spacer()
                Button(L("New Script Widget")) {
                    if let u = try? ScriptWidgetStore.shared.createSample() { NSWorkspace.shared.activateFileViewerSelecting([u]); state.refresh() }
                }
                Button(L("Install…"), action: pick)
                Button(L("Reload")) { state.refresh() }
            }
            Text(L("Widgets written in JavaScript. They run only while they are on the bar and can only do what their permissions allow."))
                .font(.callout).foregroundStyle(.secondary)
            if state.widgets.isEmpty {
                Text(L("No script widgets yet.")).foregroundStyle(.secondary)
            }
            ForEach(state.widgets) { w in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(w.name).font(.body.weight(.semibold))
                        if let d = w.description { Text(d).font(.callout).foregroundStyle(.secondary) }
                        Text(permissions(w)).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: "{ \"type\": \"widget\", \"widget\": \"script:\(w.id)\" }")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Toggle(L("On the Bar"), isOn: Binding(get: { s.strip.contains("script:" + w.id) }, set: { _ in s.toggle("script:" + w.id) }))
                        .toggleStyle(.switch).labelsHidden()
                    Button(L("Publish…")) { PublishWindow.open(Submission.widget(w)) }
                    Button(L("Show in Finder")) { if let u = w.baseURL { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                    Button(L("Remove"), role: .destructive) {
                        s.strip.removeAll { $0 == "script:" + w.id }
                        ScriptWidgetStore.shared.delete(w.id)
                        state.refresh()
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }
        }
        .alert(item: $state.pending) { w in
            Alert(title: Text(String(format: L("Install “%@”?"), w.name)),
                  message: Text(permissions(w)),
                  primaryButton: .default(Text(L("Install"))) {
                      if let u = w.baseURL { _ = try? ScriptWidgetStore.shared.install(u) }
                      state.refresh()
                  },
                  secondaryButton: .cancel())
        }
    }

    private func permissions(_ w: ScriptWidgetInfo) -> String {
        let l = (w.permissions ?? []).compactMap { ScriptWidgetInfo.permissionNames[$0].map { L($0) } }
        return l.isEmpty ? L("Needs no permissions.") : L("May:") + " " + l.joined(separator: ", ")
    }

    /// The permissions are shown before anything is copied.
    private func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.message = L("Choose a widget folder (with widget.json).")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        if let w = try? ScriptWidgetStore.load(url) { state.pending = w } else { m.message = L("That folder has no readable widget.json.") }
    }
}

private final class ScriptSectionState: ObservableObject {
    @Published var widgets = ScriptWidgetStore.shared.all
    @Published var pending: ScriptWidgetInfo?

    func refresh() {
        ScriptWidgetStore.shared.reload()
        widgets = ScriptWidgetStore.shared.all
    }
}
