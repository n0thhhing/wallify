import AppKit

// Setting menu items carry tag 1000 + key * 100 + value; both menus decode it with settingTag(_:).
private let settingTagBase = 1000

@MainActor func settingMenuItem(_ key: Int32, target: AnyObject, action: Selector) -> NSMenuItem {
    let spec = settingSpec(key)!
    let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
    if case .choice = spec.storage {
        let submenu = NSMenu(title: spec.title)
        submenu.autoenablesItems = false
        for (value, label) in spec.labels.enumerated() {
            let option = NSMenuItem(title: label, action: action, keyEquivalent: "")
            option.target = target
            option.tag = settingTagBase + Int(key) * 100 + value
            submenu.addItem(option)
        }
        item.submenu = submenu
    } else {
        item.action = action
        item.target = target
        item.tag = settingTagBase + Int(key) * 100
    }
    return item
}

func settingTag(_ tag: Int) -> (spec: SettingSpec, value: Int32)? {
    guard tag >= settingTagBase, let spec = settingSpec(Int32((tag - settingTagBase) / 100)) else { return nil }
    return (spec, Int32((tag - settingTagBase) % 100))
}

// Checkmarks follow the snapshot: a toggle is on when enabled, a choice when it is the current value.
@MainActor func updateSettingStates(_ menu: NSMenu, _ snapshot: WallifySettingsSnapshot) {
    for item in menu.items {
        if let submenu = item.submenu { updateSettingStates(submenu, snapshot) }
        guard let (spec, value) = settingTag(item.tag) else { continue }
        if spec.key == 14 { item.isEnabled = !snapshot.position_locked }
        switch spec.storage {
        case .bool(_, let field): item.state = snapshot[keyPath: field] ? .on : .off
        case .choice(_, let field): item.state = snapshot[keyPath: field] == value ? .on : .off
        }
    }
}

// Both menus share one layout: playback, widget settings, Quick Preferences, Lock Position, then Open, Settings and Quit.
@MainActor func addSettingsSection(to menu: NSMenu, target: AnyObject, action: Selector) {
    for key: Int32 in [14, 13, 15] { menu.addItem(settingMenuItem(key, target: target, action: action)) }
    let preferences = NSMenu(title: "Quick Preferences")
    preferences.autoenablesItems = false
    for key: Int32 in [5, 0, 1, 2, 3] { preferences.addItem(settingMenuItem(key, target: target, action: action)) }
    preferences.addItem(.separator())
    preferences.addItem(settingMenuItem(10, target: target, action: action))
    let quick = NSMenuItem(title: preferences.title, action: nil, keyEquivalent: "")
    quick.submenu = preferences
    menu.addItem(quick)
    menu.addItem(settingMenuItem(25, target: target, action: action))
}

@MainActor final class WidgetContextMenu: NSObject {
    static let shared = WidgetContextMenu()
    private var showing = false

    @objc func choose(_ sender: NSMenuItem) {
        wallify_context_menu_selected(Int32(sender.tag))
    }

    func build(_ snapshot: WallifySettingsSnapshot) -> NSMenu {
        let menu = NSMenu(title: "Wallify")
        menu.autoenablesItems = false
        func item(_ title: String, _ tag: Int, _ symbol: String? = nil) -> NSMenuItem {
            let result = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            result.target = self
            result.tag = tag
            if let symbol { result.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
            return result
        }
        menu.addItem(item(snapshot.playing ? "Pause" : "Play", 1, snapshot.playing ? "pause.fill" : "play.fill"))
        menu.addItem(item("Previous Track", 2, "backward.fill"))
        menu.addItem(item("Next Track", 3, "forward.fill"))
        if let liked = likeStore.state {
            menu.addItem(item(liked ? "Remove from Liked Songs" : "Save to Liked Songs", 6, liked ? "heart.fill" : "heart"))
        }
        menu.addItem(.separator())
        addSettingsSection(to: menu, target: self, action: #selector(choose(_:)))
        menu.addItem(.separator())
        menu.addItem(item(snapshot.media_source == 2 ? "Open Spotifast" : "Open Spotify", 4, "arrow.up.forward.app"))
        if let update = updateChecker.available {
            menu.addItem(item("Update Available: \(update.version.replacingOccurrences(of: "Version ", with: ""))…", 7, "arrow.down.circle"))
        }
        let settings = item("Settings…", 90, "gearshape")
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Wallify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        updateSettingStates(menu, snapshot)
        return menu
    }

    func show() {
        guard !showing else { return }
        showing = true
        defer {
            clearContextMenuEvent()
            showing = false
        }
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        let menu = build(snapshot)
        // Anchor to the screen so AppKit can lay out the menu beyond the widget.
        let event = WidgetView.contextEvent
        let location = event.flatMap { $0.window?.convertPoint(toScreen: $0.locationInWindow) }
        menu.popUp(positioning: nil, at: location ?? NSEvent.mouseLocation, in: nil)
    }
}

@_cdecl("wallify_show_context_menu")
public func showWidgetContextMenu() {
    // AppKit menu tracking must run on the main thread.
    if Thread.isMainThread {
        MainActor.assumeIsolated { WidgetContextMenu.shared.show() }
    } else {
        DispatchQueue.main.async { WidgetContextMenu.shared.show() }
    }
}
