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
    private var toggles: [Int: NSMenuItem] = [:]
    private var choices: [Int: [NSMenuItem]] = [:]
    private let toggleFields: [Int: KeyPath<WallifySettingsSnapshot, Bool>] = [
        0: \.glow, 1: \.aurora, 2: \.animations, 5: \.native_glass, 3: \.dim_paused, 25: \.position_locked
    ]
    private let choiceFields: [Int: KeyPath<WallifySettingsSnapshot, Int32>] = [
        13: \.media_source, 14: \.widget_mode, 15: \.idle_style,
        10: \.frame_strength
    ]
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
        addChoices("Widget Size", key: 14, titles: ["1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"], in: menu)
        addChoices("Media Source", key: 13, titles: ["Now Playing", "Spotify", "Spotifast", "Auto"], in: menu)
        addChoices("Companion", key: 15, titles: ["Pixel Cat", "Banana Cat", "Spotify Launcher", "Raccoon"], in: menu)
        let quick = submenu("Quick Preferences", in: menu)
        for (key, title) in [(5, "Native Glass"), (0, "Artwork Glow"), (1, "Aurora"), (2, "Animations"), (3, "Dim Artwork When Paused")] {
            toggles[key] = add(title, #selector(toggle(_:)), in: quick)
            toggles[key]?.tag = key
        }
        quick.addItem(.separator())
        addChoices("Frame Strength", key: 10, titles: ["Off", "Subtle", "Strong"], in: quick)
        toggles[25] = add("Lock Position", #selector(toggle(_:)))
        toggles[25]?.tag = 25
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
    private func add(_ title: String, _ action: Selector? = nil, shortcut: String = "", symbol: String? = nil,
                     in parent: NSMenu? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        (parent ?? menu).addItem(item)
        return item
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        add(title, in: parent).submenu = child
        return child
    }

    private func addChoices(_ title: String, key: Int, titles: [String], in parent: NSMenu) {
        let child = submenu(title, in: parent)
        choices[key] = titles.enumerated().map { value, title in
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = key * 100 + value
            child.addItem(item)
            return item
        }
    }

    func refresh() {
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        for (key, field) in toggleFields {
            toggles[key]?.state = snapshot[keyPath: field] ? .on : .off
        }
        for (key, field) in choiceFields {
            for (value, item) in (choices[key] ?? []).enumerated() {
                item.state = Int32(value) == snapshot[keyPath: field] ? .on : .off
            }
        }
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

    @objc func toggle(_ sender: NSMenuItem) {
        guard let field = toggleFields[sender.tag] else { return }
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        wallify_settings_apply_bool(Int32(sender.tag), !snapshot[keyPath: field])
        refresh()
    }

    @objc func choose(_ sender: NSMenuItem) {
        let key = sender.tag / 100, value = sender.tag % 100
        guard let items = choices[key], items.indices.contains(value) else { return }
        wallify_settings_apply_int(Int32(key), Int32(value))
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
