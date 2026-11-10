import AppKit
import SwiftUI

// "Publish to Store…": checks a theme, layout or script widget against the store rules (themes/README.md),
// writes the folder and its index.json entry where you choose, and opens GitHub's upload page. GlassBar never
// signs in or sends anything itself; the pull request is opened by you on github.com.

struct Submission {
    enum Kind: String {
        case themes, layouts, widgets
        var main: String { self == .themes ? "theme.json" : self == .layouts ? "layout.json" : "widget.json" }
    }

    let kind: Kind
    var id: String
    var name: String
    var author: String
    var version: Int
    var description: String
    var category = ""
    /// published file name → contents
    var files: [String: Data]

    static func theme(_ t: Theme) throws -> Submission {
        var files = [String: Data]()
        if let base = t.baseURL { files = Self.read(base) }
        files["theme.json"] = try ThemeStore.shared.encode(t)
        return Submission(kind: .themes, id: t.id, name: t.name, author: t.author, version: t.version, description: "", files: files)
    }

    static func layout(_ l: BarLayout) throws -> Submission {
        var files = [String: Data]()
        if let base = l.baseURL { files = Self.read(base) }
        files["layout.json"] = try LayoutStore.encode(l)
        return Submission(kind: .layouts, id: l.id, name: l.name, author: l.author, version: l.version, description: l.description, files: files)
    }

    static func widget(_ w: ScriptWidgetInfo) -> Submission {
        Submission(kind: .widgets, id: w.id, name: w.name, author: w.author ?? "", version: w.version ?? 1, description: w.description ?? "",
                   files: w.baseURL.map(Self.read) ?? [:])
    }

    /// Top-level files of a package, hidden files left out.
    private static func read(_ folder: URL) -> [String: Data] {
        let l = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var d = [String: Data]()
        for f in l where !f.hasPrefix(".") {
            // a symlink could pull a file from elsewhere on the Mac into a public package
            guard let u = packageFile(folder, f),
                  (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(f).path)[.type] as? FileAttributeType) == .typeRegular,
                  let data = try? Data(contentsOf: u) else { continue }
            d[f] = data
        }
        return d
    }

    // MARK: checks

    struct Check: Identifiable {
        let id = UUID()
        let ok: Bool
        let text: String
        /// a warning doesn't stop publishing
        var isWarning = false
    }

    static let allowed: Set = ["json", "js", "png", "jpg", "jpeg", "gif", "pdf", "ttf", "otf", "wav", "aif", "aiff", "caf", "mp3", "m4a", "txt", "md"]

    var size: Int { files.values.reduce(0) { $0 + $1.count } }

    var checks: [Check] {
        var l: [Check] = []
        let idOK = !id.isEmpty && id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && !id.hasPrefix("-")
        l.append(Check(ok: idOK, text: idOK ? String(format: L("Id “%@” uses lowercase letters, numbers and dashes."), id)
                                         : String(format: L("Id “%@” may only use lowercase letters, numbers and dashes."), id)))
        if kind == .themes { l.append(Check(ok: !Theme.builtIns.contains { $0.id == id }, text: L("Not the id of a built-in theme."))) }
        l.append(Check(ok: !name.trimmingCharacters(in: .whitespaces).isEmpty, text: L("Has a name.")))
        l.append(Check(ok: !author.trimmingCharacters(in: .whitespaces).isEmpty, text: L("Has an author (your name or GitHub handle).")))
        l.append(Check(ok: !description.trimmingCharacters(in: .whitespaces).isEmpty, text: L("Has a one-line description.")))
        l.append(Check(ok: !category.trimmingCharacters(in: .whitespaces).isEmpty, text: L("Has a category.")))
        if kind != .widgets { l.append(Check(ok: files["preview.png"] != nil, text: L("Has preview.png, a screenshot of the bar."))) }
        if kind == .widgets {
            let script = (try? JSONDecoder().decode(ScriptWidgetInfo.self, from: files["widget.json"] ?? Data()))?.script ?? "main.js"
            l.append(Check(ok: files[script] != nil, text: String(format: L("Has its script, %@."), script)))
        }
        let odd = files.keys.filter { !Self.allowed.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
        l.append(Check(ok: odd.isEmpty, text: odd.isEmpty ? L("Only fonts, images, sounds and text files.")
                                                           : String(format: L("Files the store doesn't take: %@"), odd.joined(separator: ", "))))
        let fonts = files.keys.filter { ["ttf", "otf"].contains(($0 as NSString).pathExtension.lowercased()) }
        if !fonts.isEmpty {
            let license = files.keys.contains { $0.uppercased().hasPrefix("OFL") || $0.uppercased().hasPrefix("LICENSE") }
            l.append(Check(ok: license, text: license ? L("Fonts come with their license file.") : L("Fonts need their license file (OFL.txt or LICENSE.txt).")))
        }
        let kb = (size + 1023) / 1024
        l.append(Check(ok: kb <= 500, text: String(format: L("Size: %d KB (a few hundred KB at most)."), kb), isWarning: kb > 500))
        return l
    }

    var canPublish: Bool { checks.allSatisfy { $0.ok || $0.isWarning } }

    var indexEntry: String {
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let entry: [String: Any] = ["id": id, "name": name, "author": author, "version": version, "description": description,
                                    "category": category, "added": today, "updated": today, "files": files.keys.sorted()]
        let data = (try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes <folder>/<kind>/<id>/ with the files, plus the index entry next to it.
    func write(into folder: URL) throws -> URL {
        let to = folder.appendingPathComponent(kind.rawValue).appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: to)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: to.appendingPathComponent(name), options: .atomic) }
        try indexEntry.write(to: folder.appendingPathComponent(kind.rawValue).appendingPathComponent("\(id).index-entry.json"), atomically: true, encoding: .utf8)
        return to
    }
}

enum PublishWindow {
    private static var window: NSWindow?
    private static var delegate: CloseDelegate?

    static func open(_ s: Submission) {
        NSApp.activate(ignoringOtherApps: true)
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = String(format: L("Publish “%@”"), s.name)
        w.contentView = NSHostingView(rootView: PublishView(m: PublishModel(s)))
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

final class PublishModel: ObservableObject {
    @Published var s: Submission
    @Published var preview: NSImage?
    @Published var countdown = 0
    @Published var written: URL?
    @Published var message = ""

    init(_ s: Submission) {
        self.s = s
        preview = s.files["preview.png"].flatMap(NSImage.init(data:))
    }

    /// The real Touch Bar, a few seconds from now so you can bring Finder (or the layout's app) to the front.
    func captureTouchBar() {
        countdown = 5
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            self.countdown -= 1
            guard self.countdown == 0 else { return }
            t.invalidate()
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("glassbar-preview-\(UUID().uuidString).png")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-b", "-x", file.path]
            p.terminationHandler = { _ in
                DispatchQueue.main.async {
                    if let data = try? Data(contentsOf: file), let i = NSImage(data: data) {
                        self.s.files["preview.png"] = data
                        self.preview = i
                        self.message = L("Check that nothing private (a file name, a song, a web page) is on the bar.")
                    } else {
                        self.message = L("The Touch Bar couldn't be captured. Is the screen locked?")
                    }
                    try? FileManager.default.removeItem(at: file)
                }
            }
            try? p.run()
        }
    }

    func choosePreview() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url, let data = try? Data(contentsOf: u) else { return }
        s.files["preview.png"] = data
        preview = NSImage(data: data)
    }

    func writePackage() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = L("Save Here")
        p.message = L("Choose a folder for the package. A copy of the GlassBar repository works best.")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            written = try s.write(into: u)
            NSWorkspace.shared.activateFileViewerSelecting([written!])
            message = L("Saved. Next: upload the folder and add the entry to index.json.")
        } catch { message = error.localizedDescription }
    }

    func copyEntry() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.indexEntry, forType: .string)
        message = L("The index.json entry is on the clipboard.")
    }

    func openGitHub(_ path: String) {
        if let u = URL(string: "https://github.com/\(UpdateChecker.repository)/\(path)") { NSWorkspace.shared.open(u) }
    }
}

struct PublishView: View {
    @ObservedObject var m: PublishModel

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Id"), value: m.s.id)
                TextField(L("Name"), text: $m.s.name)
                TextField(L("Author"), text: $m.s.author)
                Stepper(value: $m.s.version, in: 1...999) { LabeledContent(L("Version"), value: "\(m.s.version)") }
                TextField(L("Description"), text: $m.s.description, prompt: Text(L("One line for the store")))
                HStack {
                    TextField(L("Category"), text: $m.s.category, prompt: Text("Retro"))
                    Menu("") {
                        ForEach(categories, id: \.self) { c in Button(c) { m.s.category = c } }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                Text(L("Raise the version when you update something that is already in the store.")).font(.caption).foregroundStyle(.secondary)
            }
            if m.s.kind != .widgets {
                Section(L("Preview")) {
                    if let p = m.preview {
                        Image(nsImage: p).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 40)
                    }
                    HStack {
                        Button(m.countdown > 0 ? String(format: L("Capturing in %d…"), m.countdown) : L("Capture Touch Bar"), action: m.captureTouchBar)
                            .disabled(m.countdown > 0)
                        Button(L("Choose Image…"), action: m.choosePreview)
                    }
                    Text(m.s.kind == .themes ? L("Put Finder in front so all previews look alike.") : L("Put the layout’s app in front."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Checks")) {
                ForEach(m.s.checks) { c in
                    Label(c.text, systemImage: c.ok ? "checkmark.circle.fill" : c.isWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .foregroundStyle(c.ok ? Color.green : c.isWarning ? Color.orange : Color.red)
                }
            }
            Section(L("In the Package")) {
                ForEach(m.s.files.keys.sorted(), id: \.self) { f in
                    HStack {
                        Text(verbatim: f).font(.callout.monospaced())
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(m.s.files[f]?.count ?? 0), countStyle: .file)).foregroundStyle(.secondary)
                        Button { m.s.files[f] = nil } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L("Leave Out"))
                            .opacity(f == m.s.kind.main ? 0 : 1).disabled(f == m.s.kind.main)
                    }
                }
                if m.s.kind == .widgets, let w = try? JSONDecoder().decode(ScriptWidgetInfo.self, from: m.s.files["widget.json"] ?? Data()) {
                    Text(w.permissionText).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Everything listed here becomes public.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Publish")) {
                step(1, L("Save the package"), done: m.written != nil) {
                    Button(L("Save Package…"), action: m.writePackage).disabled(!m.s.canPublish)
                }
                step(2, L("Upload the folder on GitHub"), done: false) {
                    Button(L("Open Upload Page")) { m.openGitHub("upload/main/\(m.s.kind.rawValue)/\(m.s.id)") }
                }
                step(3, L("Add the entry to index.json"), done: false) {
                    Button(L("Copy Entry"), action: m.copyEntry)
                    Button(L("Edit index.json")) { m.openGitHub("edit/main/\(m.s.kind.rawValue)/index.json") }
                }
                Text(L("GitHub forks the repository and opens the pull request for you. GlassBar doesn’t sign in or send anything itself; every submission is reviewed before it shows in the store."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Read the Store Guidelines")) { m.openGitHub("blob/main/\(m.s.kind == .widgets ? "docs/WIDGETS.md" : m.s.kind.rawValue + "/README.md")") }
                    .buttonStyle(.link)
            }
            if !m.message.isEmpty { Section { Text(m.message).font(.callout) } }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
    }

    private var categories: [String] {
        switch m.s.kind {
        case .themes: ["Glass", "Minimal", "Retro"]
        case .layouts: ["Developer", "Design", "Writing", "Media"]
        case .widgets: ["System", "Time", "Web", "Fun"]
        }
    }

    private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle").foregroundStyle(done ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            content()
        }
    }
}
