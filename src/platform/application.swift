import AppKit

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
        0: \.glow, 1: \.aurora, 2: \.animations, 5: \.native_glass, 3: \.dim_paused
    ]
    private let choiceFields: [Int: KeyPath<WallifySettingsSnapshot, Int32>] = [
        13: \.media_source, 14: \.widget_mode, 15: \.idle_style,
        16: \.track_transition, 10: \.frame_strength
    ]

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        let header = add("Wallify")
        header.isEnabled = false
        track.isEnabled = false
        artist.isEnabled = false
        menu.addItem(track)
        menu.addItem(artist)
        menu.addItem(.separator())
        play = add("Play", #selector(playPause))
        add("Previous Track", #selector(previous), symbol: "backward.end.fill")
        add("Next Track", #selector(next), symbol: "forward.end.fill")
        menu.addItem(.separator())

        let quick = submenu("Quick Controls")
        for (key, title) in [(1, "Aurora"), (0, "Artwork Glow"), (2, "Animations"),
                             (5, "Native Glass"), (3, "Dim Paused Artwork")] {
            let item = NSMenuItem(title: title, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = key
            quick.addItem(item)
            toggles[key] = item
        }
        addChoices("Media Source", key: 13, titles: ["Now Playing", "Spotify", "Spotifast", "Auto"])
        addChoices("Widget Mode", key: 14, titles: ["1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"])
        addChoices("Idle Companion", key: 15, titles: ["Pixel Cat", "Banana Cat", "Spotify", "Raccoon"])
        addChoices("Track Transition", key: 16, titles: ["Default", "Cinematic", "Ripple", "Card Flip", "Vinyl", "Glitch"])
        addChoices("Frame", key: 10, titles: ["Off", "Subtle", "Strong"])
        menu.addItem(.separator())
        add("Open Inspector", #selector(inspector))
        add("Settings…", #selector(settings), shortcut: ",")
        menu.addItem(.separator())
        add("Open Spotify", #selector(spotify))
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

    private func submenu(_ title: String) -> NSMenu {
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        add(title).submenu = child
        return child
    }

    private func addChoices(_ title: String, key: Int, titles: [String]) {
        let child = submenu(title)
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
    @objc private func inspector() { wallify_open_inspector() }
    @objc private func spotify() { NSWorkspace.shared.open(URL(string: "spotify:")!) }
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
