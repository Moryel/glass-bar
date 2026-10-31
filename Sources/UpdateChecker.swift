import AppKit

/// Checks the latest release on GitHub: shortly after launch and once a day. If a newer version exists,
/// an "Update available" item appears at the top of the menu; clicking it opens the release page (downloading and installing is up to the user).
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repository = "Moryel/glass-bar"
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private(set) var latestVersion: String?
    private(set) var page: URL?
    private var timer: Timer?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    /// `userInitiated`: when requested from the menu, reports the result in an alert.
    func check(userInitiated: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                if let tag, tag.compare(Self.currentVersion, options: .numeric) == .orderedDescending {
                    self.latestVersion = tag
                    self.page = page
                    SystemControl.log("update: \(tag) available (this version \(Self.currentVersion))")
                } else {
                    self.latestVersion = nil
                }
                if userInitiated { self.showResult(didCheck: tag != nil) }
            }
        }.resume()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(page ?? URL(string: "https://github.com/\(Self.repository)/releases/latest")!)
    }

    private func showResult(didCheck: Bool) {
        let alert = NSAlert()
        if let latestVersion {
            alert.messageText = String(format: L("GlassBar %@ is available"), latestVersion)
            alert.informativeText = String(format: L("You have version %@. Open the download page?"), Self.currentVersion)
            alert.addButton(withTitle: L("Download"))
            alert.addButton(withTitle: L("Later"))
        } else {
            alert.messageText = didCheck ? L("GlassBar is up to date") : L("Couldn't check for updates")
            alert.informativeText = didCheck ? String(format: L("Version %@ is the latest."), Self.currentVersion)
                                               : L("Check your internet connection and try again.")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, latestVersion != nil { openReleasePage() }
    }
}
