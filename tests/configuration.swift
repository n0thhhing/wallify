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
    precondition(withUnsafeBytes(of: debug.build_identity) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    } == WallifyBuildIdentity.label)
    precondition(debug.title_len == 10 && debug.native_glass == 1 && debug.source == 1)
    precondition(debug.layout_width == sceneLayout.width && debug.duration == pointer.pointee.global_duration)
    pointer.pointee.setting_position_locked = true
    pointer.pointee.setting_waveform = true
    for style: UInt8 in 0...3 {
        pointer.pointee.setting_idle_style = style
        for behavior: UInt8 in 0...2 {
            pointer.pointee.setting_stopped_behavior = behavior
            for stopped in [false, true] {
                pointer.pointee.media_stopped = stopped
                let current = inspectorSnapshot()
                precondition(current.clickable_names == 1 && current.position_locked == 1 && current.waveform == 1)
                precondition(current.stopped_behavior == Int32(behavior) && current.media_stopped == (stopped ? 1 : 0))
                precondition(current.stopped_hidden == (stopped && behavior == 2 ? 1 : 0))
                precondition(current.idle_style == (style == 0 ? 2 : style == 1 ? 0 : style == 2 ? 1 : 3))
            }
        }
    }
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
    checkConfigurationGolden()
}

// Pins every setting's config spelling so refactors of the settings plumbing cannot drift.
func checkConfigurationGolden() {
    let position = ["widget_margin_left": "0", "widget_margin_top": "0", "widget_grid_x": "0", "widget_grid_y": "0"]
    let bools = ["artwork_glow", "native_glass", "aurora", "animations", "dim_paused_artwork", "widget_debug", "hide_text",
                 "hide_progress", "show_controls", "show_timestamps", "artwork_border", "compact_gradient", "waveform",
                 "clickable_names", "position_locked", "lyrics"]
    var low = WallifyWidgetState()
    var expected = position.merging(Dictionary(uniqueKeysWithValues: bools.map { ($0, "false") })) { $1 }
    expected.merge(["frame_strength": "off", "glow_intensity": "low", "animation_speed": "slow", "media_source": "now_playing",
                     "widget_mode": "1x1", "idle_style": "spotify", "track_transition": "default", "font_scale": "small",
                     "media_key_target": "off", "stopped_behavior": "companion", "artwork_radius": "0", "progress_thickness": "0",
                     "scroll_action": "off"]) { $1 }
    precondition(configurationValues(low) == expected)
    for path: WritableKeyPath<WallifyWidgetState, Bool> in [\.setting_glow, \.setting_native_glass, \.setting_aurora, \.setting_animations,
        \.setting_dim, \.setting_debug, \.setting_hide_text, \.setting_hide_progress, \.setting_show_controls, \.setting_show_timestamps,
        \.setting_artwork_border, \.setting_compact_gradient, \.setting_waveform, \.setting_clickable_names, \.setting_position_locked,
        \.setting_lyrics] {
        low[keyPath: path] = true
    }
    low.setting_frame = 2; low.setting_intensity = 2; low.setting_speed = 2; low.setting_source = 3; low.setting_mode = 4
    low.setting_idle_style = 3; low.setting_transition = 5; low.setting_font_scale = 2; low.setting_media_key_target = 3
    low.setting_stopped_behavior = 2; low.setting_artwork_radius = 2; low.setting_progress_thickness = 2
    expected.merge(Dictionary(uniqueKeysWithValues: bools.map { ($0, "true") })) { $1 }
    expected.merge(["frame_strength": "strong", "glow_intensity": "high", "animation_speed": "fast", "media_source": "auto",
                     "widget_mode": "2x2", "idle_style": "raccoon", "track_transition": "glitch", "font_scale": "large",
                     "media_key_target": "spotifast", "stopped_behavior": "hide", "artwork_radius": "2", "progress_thickness": "2"]) { $1 }
    precondition(configurationValues(low) == expected)
    low.setting_frame = 9; low.setting_mode = 9
    precondition(configurationValues(low)["frame_strength"] == "subtle" && configurationValues(low)["widget_mode"] == "3x1")
    var parsed = WallifyWidgetState()
    parseConfiguration("""
    widget_mode = medium
    idle_style = banana
    track_transition = card_flip
    media_key_target = active
    frame_strength = bogus
    progress_thickness = 2
    hide_text = on
    waveform = maybe
    """, into: &parsed)
    precondition(parsed.setting_mode == 1 && parsed.setting_idle_style == 2 && parsed.setting_transition == 3)
    precondition(parsed.setting_media_key_target == 1 && parsed.setting_frame == 1 && parsed.setting_progress_thickness == 2)
    precondition(parsed.setting_hide_text && !parsed.setting_waveform)
    parseConfiguration("scroll_action = seek", into: &parsed)
    precondition(parsed.setting_scroll_action == 2 && configurationValues(parsed)["scroll_action"] == "seek")
    // A trackpad swipe of 10 px is one line: 2 % volume or 2 s; natural scrolling flips the sign back.
    precondition(scrollAmount(deltaY: 10, precise: true, inverted: false) == 2)
    precondition(scrollAmount(deltaY: 10, precise: true, inverted: true) == -2)
    precondition(scrollAmount(deltaY: -1, precise: false, inverted: false) == -2)
    precondition(volumeScript(target: 140) == "set volume output volume 100" && volumeScript(target: -5) == "set volume output volume 0")
    let lyrics = parseSyncedLyrics("[ar:NEET]\n[00:13.13]Yeah\n[00:16.56]\n[01:02.50][00:20.00]Twice\nplain line")
    precondition(lyrics.map(\.time) == [13.13, 16.56, 20, 62.5] && lyrics.map(\.text) == ["Yeah", "", "Twice", "Twice"])
    precondition(!renderConfiguration(parsed).contains("[Other]") && configurationValues(parsed)["lyrics"] == "false")
    // Every current setting is documented in the config template, so nothing lands in the fallback section.
    precondition(!renderConfiguration(parsed).contains("[Other]"))
}
