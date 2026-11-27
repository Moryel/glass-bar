import AppKit
import Security

/// Checks the latest release on GitHub: shortly after launch and once a day. If a newer version exists,
/// an "Update available" item appears at the top of the menu; clicking it opens the release page.
/// With "Install Updates Automatically" on, the release's GlassBar.zip is downloaded instead, checked to be signed
/// by the same certificate as the running app, put in place of it and opened.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repository = "Moryel/glass-bar"
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private(set) var latestVersion: String?
    private(set) var page: URL?
    private var timer: Timer?
    private var isInstalling = false

    static var installsAutomatically: Bool {
        get { Defaults.bool("autoUpdate", false) }
        set { Defaults.set("autoUpdate", newValue) }
    }

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
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            let zip = (json?["assets"] as? [[String: Any]])?.first { $0["name"] as? String == "GlassBar.zip" }
                .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
            DispatchQueue.main.async {
                if let tag, tag.compare(Self.currentVersion, options: .numeric) == .orderedDescending {
                    self.latestVersion = tag
                    self.page = page
                    SystemControl.log("update: \(tag) available (this version \(Self.currentVersion))")
                    if Self.installsAutomatically, !userInitiated, let zip { self.install(tag, from: zip) }
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

    // MARK: installing

    /// Downloads, checks and installs a release, then opens the new copy. Anything that doesn't check out leaves
    /// the menu's "Update available" item as the way to update.
    func install(_ version: String, from zip: URL) {
        guard !isInstalling, zip.scheme == "https", ["github.com", "objects.githubusercontent.com"].contains(zip.host ?? ""),
              let requirement = Self.ownRequirement() else { return }
        isInstalling = true
        SystemControl.log("update: downloading \(version)")
        URLSession.shared.downloadTask(with: zip) { file, response, error in
            let result: String
            if let file, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Self.replaceApp(with: file, version: version, requirement: requirement)
            } else {
                result = "download failed (\(error?.localizedDescription ?? "no file"))"
            }
            DispatchQueue.main.async {
                self.isInstalling = false
                SystemControl.log("update: \(result)")
                if result == "installed" { Self.relaunch() }
            }
        }.resume()
    }

    /// The running app's designated requirement: its id and its certificate. An ad hoc build has only its own hash
    /// here, which no other build meets, so it never replaces itself.
    private static func ownRequirement() -> SecRequirement? {
        var code: SecCode?, file: SecStaticCode?, req: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code, SecCodeCopyStaticCode(code, [], &file) == errSecSuccess, let file,
              SecCodeCopyDesignatedRequirement(file, [], &req) == errSecSuccess else { return nil }
        return req
    }

    /// Runs off the main thread. Returns "installed" or what went wrong.
    private static func replaceApp(with file: URL, version: String, requirement: SecRequirement) -> String {
        let fm = FileManager.default
        guard ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) < 60_000_000 else { return "zip too large" }
        let temp = fm.temporaryDirectory.appendingPathComponent("GlassBar-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", file.path, temp.path]
        guard (try? p.run()) != nil else { return "could not unzip" }
        p.waitUntilExit()
        let app = temp.appendingPathComponent("GlassBar.app")
        guard p.terminationStatus == 0, (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else {
            return "no GlassBar.app in the zip"
        }
        // signed by the same certificate as this copy, and every file intact
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode),
                                         requirement) == errSecSuccess else {
            return "signature doesn't match this copy, not installed"
        }
        let new = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard new == version, new.compare(currentVersion, options: .numeric) == .orderedDescending else {
            return "version \(new) in the zip isn't \(version), not installed"
        }
        do {
            _ = try fm.replaceItemAt(Bundle.main.bundleURL, withItemAt: app, backupItemName: nil, options: [])
        } catch {
            return "could not replace the app: \(error.localizedDescription)"
        }
        return "installed"
    }

    /// Testing without GitHub: -testUpdateZip <path> -testUpdateVersion <version>
    func installLocal(_ zip: URL, version: String) {
        guard let requirement = Self.ownRequirement() else { return }
        DispatchQueue.global().async {
            let result = Self.replaceApp(with: zip, version: version, requirement: requirement)
            DispatchQueue.main.async {
                SystemControl.log("update: \(result)")
                if result == "installed" { Self.relaunch() }
            }
        }
    }

    /// Opens the new copy once this one has quit.
    private static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open -g \"$0\"",
                       Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
