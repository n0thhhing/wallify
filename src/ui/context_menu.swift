import AppKit

@MainActor final class WidgetContextMenu: NSObject {
    static let shared = WidgetContextMenu()
    private var showing = false

    @objc func choose(_ sender: NSMenuItem) {
        wallify_context_menu_selected(Int32(sender.tag))
    }

    func build(_ snapshot: WallifySettingsSnapshot) -> NSMenu {
        let menu = NSMenu(title: "Wallify")
        menu.autoenablesItems = false
        func item(_ title: String, _ tag: Int, _ selected: Bool = false) -> NSMenuItem {
            let result = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            result.target = self
            result.tag = tag
            result.state = selected ? .on : .off
            return result
        }
        func group(_ title: String, _ labels: [String], _ tags: [Int], _ selected: Int32,
                   _ values: [Int32]? = nil, in parent: NSMenu) {
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            for index in labels.indices {
                submenu.addItem(item(labels[index], tags[index], selected == (values?[index] ?? Int32(index))))
            }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = submenu
            parent.addItem(entry)
        }
        for (title, tag) in [(snapshot.playing ? "Pause" : "Play", 1), ("Previous Track", 2),
                             ("Next Track", 3), (snapshot.media_source == 2 ? "Open Spotifast" : "Open Spotify", 4)] {
            menu.addItem(item(title, tag))
        }
        menu.addItem(.separator())
        let settings = item("Settings…", 90)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("Lock Position", 9, snapshot.position_locked))
        menu.addItem(.separator())
        group("Media Source", ["Now Playing", "Spotify", "Spotifast"], [50, 51, 52], snapshot.media_source, in: menu)
        group("Widget Size", ["1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"],
              [60, 61, 62, 63, 64], snapshot.widget_mode, in: menu)
        group("Companion", ["Pixel Cat", "Banana Cat", "Raccoon", "Spotify Launcher"],
              [81, 82, 83, 80], snapshot.idle_style, [0, 1, 3, 2], in: menu)
        menu.addItem(.separator())
        let preferences = NSMenu(title: "Quick Preferences")
        preferences.autoenablesItems = false
        for (title, tag, enabled) in [("Artwork Glow", 5, snapshot.glow), ("Dynamic Aurora", 6, snapshot.aurora),
                                      ("Animations", 7, snapshot.animations), ("Dim Artwork When Paused", 8, snapshot.dim_paused)] {
            preferences.addItem(item(title, tag, enabled))
        }
        preferences.addItem(.separator())
        group("Frame Strength", ["Off", "Subtle", "Strong"], [10, 11, 12], snapshot.frame_strength, in: preferences)
        let quick = NSMenuItem(title: preferences.title, action: nil, keyEquivalent: "")
        quick.submenu = preferences
        menu.addItem(quick)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Wallify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApplication.shared
        menu.addItem(quit)
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
        if let event = WidgetView.contextEvent, let view = WidgetView.current {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            // Without an event, AppKit expects screen coordinates with no view.
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

@_cdecl("wallify_show_context_menu")
public func showWidgetContextMenu() {
    // Right-click tracking must begin in the originating main-thread handler.
    if Thread.isMainThread {
        MainActor.assumeIsolated { WidgetContextMenu.shared.show() }
    } else {
        DispatchQueue.main.async { WidgetContextMenu.shared.show() }
    }
}
