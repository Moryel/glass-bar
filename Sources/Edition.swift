import AppKit

/// GlassBar or GlassBar Beta (`./build.sh beta` compiles with -D BETA). The beta has its own bundle id,
/// so UserDefaults are separate already; files go to their own folder too.
enum Edition {
    #if BETA
    static let isBeta = true
    static let name = "GlassBar Beta"
    #else
    static let isBeta = false
    static let name = "GlassBar"
    #endif

    static let releaseBundleID = "com.yukselozge.GlassBar"

    static let supportFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(name, isDirectory: true)
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name).log")

    /// First launch of the beta: start from a copy of the normal app's settings and themes (read only, nothing is changed there).
    static func importReleaseSettings() {
        let d = UserDefaults.standard
        guard isBeta, !d.bool(forKey: "importedReleaseSettings") else { return }
        for (key, value) in d.persistentDomain(forName: releaseBundleID) ?? [:] where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
        let fm = FileManager.default
        let release = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassBar", isDirectory: true)
        for sub in ["Themes", "Layouts"] where !fm.fileExists(atPath: supportFolder.appendingPathComponent(sub).path) {
            try? fm.createDirectory(at: supportFolder, withIntermediateDirectories: true)
            try? fm.copyItem(at: release.appendingPathComponent(sub), to: supportFolder.appendingPathComponent(sub))
        }
        d.set("dock", forKey: "barMode")
        d.set(true, forKey: "importedReleaseSettings")
    }

    /// Only one GlassBar drives the Touch Bar: the beta quits the normal app. Returns whether one was running.
    @discardableResult
    static func quitReleaseApp() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: releaseBundleID)
        running.forEach { $0.terminate() }
        return !running.isEmpty
    }

    static func switchToReleaseApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: releaseBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
