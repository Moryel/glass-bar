import AppKit
import SwiftUI

// Send Feedback: a short form that opens a filled-in GitHub issue. Nothing is sent from the app; the issue page
// shows everything, and people post it from their own account or close the tab.

enum FeedbackWindow {
    private static var window: NSWindow?
    private static var delegate: CloseDelegate?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = L("Send Feedback")
        let h = NSHostingView(rootView: FeedbackView { w.performClose(nil) })
        // the text box would otherwise make the window as tall as it likes
        h.sizingOptions = [.minSize]
        w.contentView = h
        w.contentMinSize = NSSize(width: 420, height: 400)
        w.isReleasedWhenClosed = false
        w.center()
        delegate = CloseDelegate { [weak w] in
            window = nil; delegate = nil
            DispatchQueue.main.async { w?.contentView = nil }
        }
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

enum Feedback {
    enum Kind: String, CaseIterable { case bug, idea }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    static var version: String { (Edition.isBeta ? "Beta " : "") + UpdateChecker.currentVersion }

    /// The end of the log, for a bug report. Lines can name themes, widgets and apps, so it's only added when asked.
    static func logTail(_ lines: Int = 30) -> String {
        guard let s = try? String(contentsOf: Edition.logURL, encoding: .utf8) else { return "" }
        return s.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }

    /// The new-issue page with the form's fields filled in (the ids in .github/ISSUE_TEMPLATE).
    static func issueURL(kind: Kind, text: String, steps: String, log: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let title = firstLine.count > 70 ? String(firstLine.prefix(69)) + "…" : firstLine
        var fields: [(String, String)] = [("title", title)]
        switch kind {
        case .bug:
            fields += [("template", "bug_report.yml"), ("what", text), ("steps", steps),
                       ("mac", Hardware.model), ("macos", macOS), ("version", version)]
        case .idea:
            fields += [("template", "feature_request.yml"), ("idea", text)]
        }
        var c = URLComponents(string: "https://github.com/\(UpdateChecker.repository)/issues/new")!
        c.queryItems = fields.filter { !$0.1.isEmpty }.map { URLQueryItem(name: $0.0, value: $0.1) }
        // GitHub turns away very long addresses; the log is what gives way
        var log = log
        while !log.isEmpty {
            var withLog = c
            withLog.queryItems?.append(URLQueryItem(name: "log", value: log))
            if let u = encoded(withLog), u.absoluteString.count <= 7500 { return u }
            log = log.split(separator: "\n").dropFirst(5).joined(separator: "\n")
        }
        return encoded(c)
    }

    /// URLComponents leaves "+" alone, and GitHub reads it as a space ("+0000" in the log, "C++" in a title).
    private static func encoded(_ c: URLComponents) -> URL? {
        var c = c
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }
}

final class FeedbackModel: ObservableObject {
    @Published var kind = Feedback.Kind.bug
    @Published var text = ""
    @Published var steps = ""
    @Published var addsLog = false
}

struct FeedbackView: View {
    let close: () -> Void
    @StateObject private var m = FeedbackModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $m.kind) {
                Text(L("Something's wrong")).tag(Feedback.Kind.bug)
                Text(L("An idea")).tag(Feedback.Kind.idea)
            }
            .pickerStyle(.segmented).labelsHidden()

            Text(m.kind == .bug ? L("What happened, and what did you expect?") : L("What would you like the Touch Bar to show or do?"))
                .font(.headline)
            TextEditor(text: $m.text)
                .font(.body).scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .frame(minHeight: 120, maxHeight: .infinity)

            if m.kind == .bug {
                TextField(L("How to make it happen (optional)"), text: $m.steps, axis: .vertical)
                    .lineLimit(2...4)
                Toggle(L("Add the last lines of the log"), isOn: $m.addsLog)
                Text(String(format: L("Added: %@, %@, GlassBar %@."), Hardware.model, Feedback.macOS, Feedback.version))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(L("GitHub opens with this filled in. You see everything there before posting, and you need a GitHub account to post."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Button(L("Continue on GitHub")) {
                    if let u = Feedback.issueURL(kind: m.kind, text: m.text, steps: m.steps, log: m.addsLog ? Feedback.logTail() : "") {
                        NSWorkspace.shared.open(u)
                        close()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 400)
    }
}
