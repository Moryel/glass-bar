import AppKit

// Safari's open windows and tabs (AppleScript; asks for Automation permission on first use).
struct SafariTab: Equatable, Identifiable {
    var window: Int
    var index: Int
    var name: String
    var address: String
    var isSelected: Bool

    var id: String { "\(window).\(index)" }

    /// Called on the work queue. One line each: window, index, selected, title, URL (tab-separated).
    /// nil if Safari can't be reached (no Automation permission).
    static func read() -> [SafariTab]? {
        // inside Safari `tab` means a tab object, so the tab-character separator is defined outside
        let runScript = """
        set ayr to character id 9
        tell application "Safari"
            set s to ""
            repeat with w from 1 to count windows
                try
                    set pen to window w
                    set ct to index of current tab of pen
                    set i to 0
                    repeat with t in tabs of pen
                        set i to i + 1
                        set u to ""
                        try
                            set u to URL of t
                        end try
                        set ad to ""
                        try
                            set ad to name of t
                        end try
                        set s to s & w & ayr & i & ayr & ((i = ct) as text) & ayr & ad & ayr & u & linefeed
                    end repeat
                end try
            end repeat
            return s
        end tell
        """
        guard let result = SystemControl.runScript(runScript) else { return nil }
        let text = result.stringValue ?? ""
        var windowNumbers: [Int: Int] = [:]
        return text.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5, let w = Int(p[0]), let i = Int(p[1]) else { return nil }
            // keep numbers sequential (1, 2, 3) when hidden/empty windows are skipped
            let n = windowNumbers[w] ?? { let n = windowNumbers.count + 1; windowNumbers[w] = n; return n }()
            return SafariTab(window: n, index: i, name: p[3], address: URL(string: p[4])?.host ?? p[4], isSelected: p[2] == "true")
                .withScriptWindow(w)
        }
    }

    /// Window number in AppleScript (may differ from the index shown on the bar).
    private(set) var scriptWindowIndex = 0

    private func withScriptWindow(_ w: Int) -> SafariTab {
        var s = self
        s.scriptWindowIndex = w
        return s
    }

    /// Switches to this tab and brings its window to the front. Called on the work queue.
    func select() {
        SystemControl.runScript("""
        tell application "Safari"
            set pen to window \(scriptWindowIndex)
            set current tab of pen to tab \(index) of pen
            set index of pen to 1
            activate
        end tell
        """)
    }
}
