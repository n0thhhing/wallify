import AppKit

// Compares the running version with the latest GitHub release of n0thhhing/wallify. GitHub's
// "latest" release already excludes drafts and pre-releases. Nothing is downloaded or installed:
// a newer release shows "Update Available…" in the menus and Settings, which opens its page.
final class UpdateChecker: @unchecked Sendable {
    static let releasesURL = URL(string: "https://api.github.com/repos/n0thhhing/wallify/releases/latest")!
    private let lock = NSLock()
    private var latest: (version: String, page: URL)?
    private var checking = false
    private var timer: Timer?
    private var statusText = "Not checked yet"

    var lastStatus: String { lock.lock(); defer { lock.unlock() }; return statusText }
    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    // The newer release, or nil when up to date or not checked.
    var available: (version: String, page: URL)? {
        lock.lock(); defer { lock.unlock() }
        guard let latest, compareVersions(latest.version, current) > 0 else { return nil }
        return latest
    }

    // Checks 30 s after launch, then daily, while the setting is on.
    @MainActor func start() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in checkIfEnabled() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [self] _ in checkIfEnabled() }
    }

    private func checkIfEnabled() {
        sceneLock.lock()
        let enabled = widgetStatePointer().pointee.setting_check_updates
        sceneLock.unlock()
        if enabled { check() }
    }

    func check() {
        lock.lock()
        guard !checking else { lock.unlock(); return }
        checking = true
        statusText = "Checking…"
        lock.unlock()
        refreshSettingsUI()
        var request = URLRequest(url: Self.releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wallify", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = status == 200 ? data.flatMap(parseLatestRelease) : nil
            lock.lock()
            checking = false
            if let release { latest = release }
            let newer = latest.map { compareVersions($0.version, current) > 0 } ?? false
            statusText = release == nil ? (status == 404 ? "No releases published yet" : "Could not reach GitHub") :
                newer ? "Version \(release!.version) is available" : "Up to date"
            lock.unlock()
            refreshSettingsUI()
        }.resume()
    }

    func openRelease() {
        guard let page = available?.page else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(page) }
    }
}

let updateChecker = UpdateChecker()

func parseLatestRelease(_ data: Data) -> (version: String, page: URL)? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
          page.host == "github.com" else { return nil }
    return (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page)
}

// Numeric, dot-separated comparison: 1.10.0 > 1.9.0 and 1.2 == 1.2.0. Non-numeric parts count as 0.
func compareVersions(_ a: String, _ b: String) -> Int {
    let left = a.split(separator: ".").map { Int($0) ?? 0 }, right = b.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
        let x = index < left.count ? left[index] : 0, y = index < right.count ? right[index] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}
