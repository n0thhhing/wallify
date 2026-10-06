import Foundation

@MainActor func checkSharedStateAndInspector() {
    let pointer = widgetStatePointer(), original = pointer.pointee
    defer { pointer.pointee = original }
    pointer.pointee.setting_source = 1
    pointer.pointee.global_rate = 0
    pointer.pointee.media_stopped = false
    updateTrackText(Array("Spotify".utf8), [], state: pointer)
    _ = stateFlag(0, 1, false); _ = stateFlag(1, 1, true)
    precondition(!spotifyIsIdle()) // A paused, present track keeps the player visible.
    _ = stateFlag(1, 1, false)
    pointer.pointee.media_stopped = true
    precondition(spotifyIsIdle())
    _ = stateFlag(0, 1, true)
    precondition(spotifyIsIdle())
    _ = stateFlag(0, 1, false)
    pointer.pointee.setting_idle_style = 3
    pointer.pointee.setting_native_glass = true
    pointer.pointee.media_stopped = false
    pointer.pointee.setting_clickable_names = true
    updateTrackText(Array("Track 🎵".utf8), Array("Artist".utf8), state: pointer)
    var snapshot = WallifySettingsSnapshot()
    widgetSettingsSnapshot(&snapshot)
    precondition(snapshot.idle_style == 3 && snapshot.native_glass && snapshot.media_source == 1 && snapshot.clickable_names)
    precondition(withUnsafeBytes(of: snapshot.title) { String(decoding: $0.prefix(10), as: UTF8.self) } == "Track 🎵")
    let debug = inspectorSnapshot()
    precondition(debug.title_len == 10 && debug.native_glass == 1 && debug.source == 1)
    precondition(debug.layout_width == sceneLayout.width && debug.duration == pointer.pointee.global_duration)
}

func checkConfigurationStorage() {
    var value = widgetStatePointer().pointee
    parseConfiguration("""
    [Appearance]
    artwork_glow = no # comment
    native_glass = yes
    show_controls = invalid
    clickable_names = true
    position_locked = true
    stopped_behavior = hide
    widget_mode = 1
    media_source = fastpotify
    widget_grid_x = 255
    widget_grid_y = 2
    artwork_radius = 300
    """, into: &value)
    precondition(!value.setting_glow && value.setting_native_glass && value.setting_show_controls)
    precondition(value.setting_clickable_names)
    precondition(value.setting_position_locked)
    precondition(value.setting_stopped_behavior == 2)
    precondition(value.setting_mode == 2 && value.setting_source == 2)
    precondition(value.widget_grid_x == 20 && value.widget_margin_left == 3608 && value.widget_margin_top == 368)
    precondition(value.setting_artwork_radius == 1)
    parseConfiguration("widget_margin_left = -2\nwidget_margin_top = -999\nwidget_grid_x = 3", into: &value)
    precondition(value.widget_margin_left == 0 && value.widget_margin_top == -180)
    let content = renderConfiguration(value)
    var restored = WallifyWidgetState()
    parseConfiguration(content, into: &restored)
    precondition(configurationValues(restored) == configurationValues(value))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wallify-config-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try! persistConfiguration("old", to: url)
    try! persistConfiguration(content, to: url)
    precondition(try! String(contentsOf: url, encoding: .utf8) == content)
    do {
        try persistConfiguration("bad", to: url.appendingPathComponent("missing/config"))
        preconditionFailure("Saving under a file should fail")
    } catch {}
    precondition(try! String(contentsOf: url, encoding: .utf8) == content)
}
