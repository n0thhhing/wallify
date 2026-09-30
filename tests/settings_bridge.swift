import AppKit

// Link the real Settings model against a small in-memory native bridge.
private var current = WallifySettingsSnapshot()
private var lastBool: (Int32, Bool)?
private var lastInt: (Int32, Int32)?
private var playbackCommands: [String] = []

@_cdecl("wallify_menu_play_pause")
func playStub() { playbackCommands.append("play_pause") }
@_cdecl("wallify_menu_previous")
func previousStub() { playbackCommands.append("previous") }
@_cdecl("wallify_menu_next")
func nextStub() { playbackCommands.append("next") }

@_cdecl("wallify_settings_get_snapshot")
func snapshotStub(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) { output?.pointee = current }

@_cdecl("wallify_settings_apply_bool")
func boolStub(_ key: Int32, _ value: Bool) {
    lastBool = (key, value)
    switch key {
    case 0: current.glow = value
    case 1: current.aurora = value
    case 2: current.animations = value
    case 3: current.dim_paused = value
    case 5: current.native_glass = value
    default: break
    }
}

@_cdecl("wallify_settings_apply_int")
func intStub(_ key: Int32, _ value: Int32) {
    lastInt = (key, value)
    switch key {
    case 10: current.frame_strength = value
    case 13: current.media_source = value
    case 14: current.widget_mode = value
    case 15: current.idle_style = value
    case 16: current.track_transition = value
    default: break
    }
}

@_cdecl("wallify_debug_renderer_stats")
func rendererStub(_ output: UnsafeMutablePointer<WallifyRendererStats>?) { output?.pointee = WallifyRendererStats() }

@_cdecl("wallify_settings_restore_defaults")
func defaultsStub() {}
@_cdecl("wallify_settings_reset_position")
func positionStub() {}
@_cdecl("wallify_open_inspector")
func inspectorStub() {}
@_cdecl("wallify_settings_path")
func pathStub() -> UnsafePointer<CChar>? { nil }

@main
struct SettingsBridgeCheck {
    @MainActor static func main() {
        let model = SettingsModel()
        current.glow = false
        current.media_source = 3
        model.refresh()
        let glow = model.toggle(0, \.glow)
        let source = model.selection(13, \.media_source)
        precondition(!glow.wrappedValue && source.wrappedValue == 3)
        glow.wrappedValue = true
        precondition(lastBool?.0 == 0 && lastBool?.1 == true && model.snapshot.glow)
        source.wrappedValue = 2
        precondition(lastInt?.0 == 13 && lastInt?.1 == 2 && model.snapshot.media_source == 2)
        current.glow = false
        current.media_source = 1
        model.refresh()
        precondition(!glow.wrappedValue && source.wrappedValue == 1)
        precondition(hasSettingsFlag() == ProcessInfo.processInfo.arguments.contains("--settings"))
        _ = NSApplication.shared
        let status = StatusMenu()
        status.refresh()
        precondition(status.menu.items[1].title == "Nothing Playing")
        precondition(status.menu.items[2].title == "Choose music to get started")
        current.playing = true
        status.refresh()
        precondition(status.play.title == "Pause")
        for (name, key) in [("Media Source", 13), ("Widget Mode", 14), ("Idle Companion", 15),
                            ("Track Transition", 16), ("Frame", 10)] {
            let items = status.menu.items.first { $0.title == name }!.submenu!.items
            for (value, item) in items.enumerated() {
                status.choose(item)
                precondition(lastInt?.0 == Int32(key) && lastInt?.1 == Int32(value))
                precondition(items.filter { $0.state == .on }.count == 1 && item.state == .on)
            }
        }
        let toggles = status.menu.items.first { $0.title == "Quick Controls" }!.submenu!.items
        for item in toggles {
            let previous = item.state
            // A stale displayed checkmark must not change the toggle's meaning.
            item.state = previous == .on ? .off : .on
            status.toggle(item)
            precondition(lastBool?.0 == Int32(item.tag))
            precondition(item.state != previous)
        }
        status.playPause(); status.previous(); status.next()
        precondition(playbackCommands == ["play_pause", "previous", "next"])
        print("Swift settings bridge checks passed")
    }
}
