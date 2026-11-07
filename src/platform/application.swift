import AppKit

private var configurationPath: NSString = "widget-settings.conf"

// Keep the existing XDG override, Application Support default, and bare-binary fallback.
func prepareConfiguration(bundleURL: URL, resourceURL: URL?, home: URL) -> String {
    guard bundleURL.pathExtension == "app" else { return "widget-settings.conf" }
    let files = FileManager.default
    let override = home.appendingPathComponent(".config/Wallify/widget-settings.conf")
    let support = home.appendingPathComponent("Library/Application Support/Wallify", isDirectory: true)
    let destination = support.appendingPathComponent("widget-settings.conf")
    do {
        try files.createDirectory(at: support, withIntermediateDirectories: true)
    } catch { NSLog("Wallify: cannot create settings directory: %@", error.localizedDescription) }
    if files.fileExists(atPath: override.path) { return override.path }
    if !files.fileExists(atPath: destination.path), let resourceURL {
        do {
            try files.copyItem(at: resourceURL.appendingPathComponent("widget-settings.conf"), to: destination)
        } catch { NSLog("Wallify: cannot seed settings: %@", error.localizedDescription) }
    }
    return destination.path
}

@_cdecl("wallify_prepare")
public func preparePlatform() {
    NSLog("Wallify: preparing native platform")
    let bundle = Bundle.main
    configurationPath = prepareConfiguration(bundleURL: bundle.bundleURL, resourceURL: bundle.resourceURL,
                                              home: FileManager.default.homeDirectoryForCurrentUser) as NSString
    if bundle.bundleURL.pathExtension == "app", let resources = bundle.resourceURL {
        if !FileManager.default.changeCurrentDirectoryPath(resources.path) {
            NSLog("Wallify: cannot enter bundle resources: %@", resources.path)
        }
    }
}

@_cdecl("wallify_settings_path")
public func configurationFilePath() -> UnsafePointer<CChar> { configurationPath.fileSystemRepresentation }

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()
    let menu = NSMenu(title: "Wallify")
    private(set) var statusItem: NSStatusItem?
    private let track = NSMenuItem(title: "Now Playing", action: nil, keyEquivalent: "")
    private let artist = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private(set) var play: NSMenuItem!
    private var timer: Timer?
    private var open: NSMenuItem!

    // Keep this order and naming in step with WidgetContextMenu.
    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        track.target = self
        track.action = #selector(spotify)  // the now-playing item opens the player
        artist.isEnabled = false
        menu.addItem(track)
        if #unavailable(macOS 14.4) { menu.addItem(artist) }
        menu.addItem(.separator())
        play = add("Play", #selector(playPause))
        add("Previous Track", #selector(previous), symbol: "backward.fill")
        add("Next Track", #selector(next), symbol: "forward.fill")
        menu.addItem(.separator())
        addSettingsSection(to: menu, target: self, action: #selector(chooseSetting(_:)))
        menu.addItem(.separator())
        open = add("Open Spotify", #selector(spotify), symbol: "arrow.up.forward.app")
        add("Settings…", #selector(settings), shortcut: ",", symbol: "gearshape")
        menu.addItem(.separator())
        let quit = add("Quit Wallify", #selector(NSApplication.terminate(_:)), shortcut: "q")
        quit.target = NSApplication.shared
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Wallify")
        item.button?.image?.isTemplate = true
        item.menu = menu
        statusItem = item
        refresh()
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector? = nil, shortcut: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        menu.addItem(item)
        return item
    }

    func refresh() {
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        updateSettingStates(menu, snapshot)
        track.title = withUnsafePointer(to: &snapshot.title) {
            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
        }
        artist.title = withUnsafePointer(to: &snapshot.artist) {
            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
        }
        if track.title.isEmpty { track.title = "Nothing Playing" }
        if artist.title.isEmpty { artist.title = "Choose music to get started" }
        if #available(macOS 14.4, *) { track.subtitle = artist.title }
        track.image = NSImage(systemSymbolName: snapshot.playing ? "waveform" : "music.note", accessibilityDescription: nil)
        open.title = snapshot.media_source == 2 ? "Open Spotifast" : "Open Spotify"
        play.title = snapshot.playing ? "Pause" : "Play"
        play.image = NSImage(systemSymbolName: snapshot.playing ? "pause.fill" : "play.fill",
                             accessibilityDescription: play.title)
        statusItem?.button?.toolTip = "Wallify · \(snapshot.playing ? "Playing" : "Paused") · \(track.title)"
    }

    @objc func chooseSetting(_ sender: NSMenuItem) {
        guard let (spec, value) = settingTag(sender.tag) else { return }
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        switch spec.storage {
        // Toggle from the current setting, not the displayed checkmark, which may be stale.
        case .bool(_, let field): wallify_settings_apply_bool(spec.key, !snapshot[keyPath: field])
        case .choice: wallify_settings_apply_int(spec.key, value)
        }
        refresh()
    }

    @objc func playPause() { wallify_menu_play_pause() }
    @objc func previous() { wallify_menu_previous() }
    @objc func next() { wallify_menu_next() }
    @objc private func settings() { showSettingsWindow() }
    @objc private func spotify() {
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        if snapshot.media_source == 2 { openSpotifast() } else { openSpotify() }
    }
    @objc private func timerRefresh(_ timer: Timer) { refresh() }

    func menuWillOpen(_ menu: NSMenu) {
        timer?.invalidate()
        refresh()
        let refreshTimer = Timer(timeInterval: 0.2, target: self, selector: #selector(timerRefresh(_:)),
                                 userInfo: nil, repeats: true)
        timer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) { timer?.invalidate(); timer = nil }
}

@_cdecl("wallify_install_status_menu")
@MainActor public func installStatusMenu() { StatusMenu.shared.install() }

@_cdecl("widget_application_init")
@MainActor public func initializeApplication() {
    NSApplication.shared.setActivationPolicy(.accessory)
}

@_cdecl("widget_application_run")
@MainActor public func runApplication() { NSApplication.shared.run() }
