import AppKit

// Checks GitHub releases of n0thhhing/wallify on the chosen channel. Stable compares versions with
// the latest full release (GitHub's "latest" excludes drafts and pre-releases); Nightly compares the
// build commit with the rolling "nightly" pre-release. Nothing is downloaded or installed: an update
// shows "Update Available…" in the menus and Settings, which opens its github.com page.
final class UpdateChecker: @unchecked Sendable {
    private let lock = NSLock()
    private var found: ReleaseCheck?
    private var checking = false
    private var timer: Timer?
    private var statusText = "Not checked yet"

    var lastStatus: String { lock.lock(); defer { lock.unlock() }; return statusText }
    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    // The newer release on the current channel, or nil when up to date or not checked.
    var available: (version: String, page: URL)? {
        lock.lock(); defer { lock.unlock() }
        return found.map { ($0.label, $0.page) }
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
        sceneLock.lock()
        let nightly = widgetStatePointer().pointee.setting_update_channel == 1
        sceneLock.unlock()
        lock.lock()
        guard !checking else { lock.unlock(); return }
        checking = true
        found = nil
        statusText = "Checking…"
        lock.unlock()
        refreshSettingsUI()
        let path = nightly ? "tags/nightly" : "latest"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/n0thhhing/wallify/releases/" + path)!, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wallify", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = status == 200 ? data.flatMap {
                evaluateRelease($0, nightly: nightly, version: current, commit: WallifyBuildIdentity.commit)
            } : nil
            lock.lock()
            checking = false
            found = release?.newer == true ? release : nil
            statusText = release == nil ? (status == 404 ? (nightly ? "No nightly build published yet" : "No releases published yet") :
                "Could not reach GitHub") : release!.newer ? "\(release!.label) is available" : "Up to date"
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

struct ReleaseCheck: Equatable {
    let label: String, page: URL, newer: Bool
}

// Reads a GitHub release. A stable release is newer by version; the nightly is newer when it was
// built from a different commit than this build (its target is the full commit SHA).
func evaluateRelease(_ data: Data, nightly: Bool, version: String, commit: String) -> ReleaseCheck? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
          page.host == "github.com" else { return nil }
    if nightly {
        guard let target = json["target_commitish"] as? String, target.count >= 7 else { return nil }
        return ReleaseCheck(label: "Nightly \(target.prefix(7))", page: page, newer: !target.hasPrefix(commit))
    }
    let released = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return ReleaseCheck(label: "Version \(released)", page: page, newer: compareVersions(released, version) > 0)
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
