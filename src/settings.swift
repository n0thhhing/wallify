import Foundation

private let boolSettingKeys: [Int32: WritableKeyPath<WallifyWidgetState, Bool>] = [
    0: \.setting_glow, 1: \.setting_aurora, 2: \.setting_animations, 3: \.setting_dim,
    4: \.setting_debug, 5: \.setting_native_glass, 6: \.setting_hide_text,
    7: \.setting_hide_progress, 8: \.setting_show_controls, 9: \.setting_show_timestamps,
    19: \.setting_artwork_border, 20: \.setting_compact_gradient, 23: \.setting_waveform,
    24: \.setting_clickable_names, 25: \.setting_position_locked
]
private let intSettingKeys: [Int32: (WritableKeyPath<WallifyWidgetState, UInt8>, Int32)] = [
    10: (\.setting_frame, 2), 11: (\.setting_intensity, 2), 12: (\.setting_speed, 2),
    13: (\.setting_source, 3), 16: (\.setting_transition, 5), 17: (\.setting_font_scale, 2),
    18: (\.setting_media_key_target, 3), 21: (\.setting_artwork_radius, 2), 22: (\.setting_progress_thickness, 2)
]

@_cdecl("wallify_native_apply_bool")
public func applyWidgetBool(_ key: Int32, _ value: Bool) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard let path = boolSettingKeys[key] else { return }
    widgetStatePointer().pointee[keyPath: path] = value
    if key == 25 && value {
        let state = widgetStatePointer()
        state.pointee.global_panel_dragging = false
        state.pointee.panel_snap_active = false; state.pointee.panel_save_after_snap = false
        DispatchQueue.main.async { widget_hide_snap_outline() }
    }
    if !value && [2, 23].contains(key) || value && key == 7 { audioWaveform.update(active: false) }
    if key == 4 { if value { widget_debug_window_show() } else { widget_debug_window_hide() } }
    saveConfiguration()
    requestWidgetFrame()
}

@_cdecl("wallify_native_apply_int")
public func applyWidgetInt(_ key: Int32, _ value: Int32) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let state = widgetStatePointer()
    if key == 14 {
        let mode = UInt8(max(0, min(4, value)))
        if state.pointee.setting_mode != mode {
            beginWidgetMode(mode, Double(wallify_width()), Double(wallify_height()), state.pointee.setting_animations)
            if !state.pointee.mode_transition_active {
                let (w, h) = modeDimensions(mode)
                resizeMetalWidget(Int32(w), Int32(h))
            }
        }
    } else if key == 15 {
        state.pointee.setting_idle_style = value == 0 ? 1 : value == 1 ? 2 : value == 3 ? 3 : 0
    } else if let (path, maximum) = intSettingKeys[key] {
        state.pointee[keyPath: path] = UInt8(max(0, min(maximum, value)))
        if key == 18 { updateMediaKeyTap(Int32(state.pointee.setting_media_key_target)) }
    } else { return }
    saveConfiguration()
    requestWidgetFrame()
}

@_cdecl("wallify_native_reset_position")
public func resetWidgetPosition() {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    widgetStatePointer().pointee.widget_margin_left = 8
    widgetStatePointer().pointee.widget_margin_top = 8
    widgetStatePointer().pointee.panel_position_dirty = true
    saveConfiguration()
    requestWidgetFrame()
}

@_cdecl("wallify_native_restore_defaults")
public func restoreWidgetDefaults() {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let state = widgetStatePointer()
    for (key, path) in boolSettingKeys { state.pointee[keyPath: path] = ![4, 5, 6, 7, 23, 24, 25].contains(key) }
    for (key, (path, _)) in intSettingKeys { state.pointee[keyPath: path] = [13, 18].contains(key) ? 0 : 1 }
    state.pointee.setting_idle_style = 1
    audioWaveform.update(active: false)
    beginWidgetMode(2, Double(wallify_width()), Double(wallify_height()), true)
    widget_debug_window_hide()
    updateMediaKeyTap(0)
    saveConfiguration()
    requestWidgetFrame()
}

private let boolSettings: [(String, WritableKeyPath<WallifyWidgetState, Bool>)] = [
    ("artwork_glow", \.setting_glow), ("native_glass", \.setting_native_glass),
    ("aurora", \.setting_aurora), ("animations", \.setting_animations),
    ("dim_paused_artwork", \.setting_dim), ("widget_debug", \.setting_debug),
    ("hide_text", \.setting_hide_text), ("hide_progress", \.setting_hide_progress),
    ("show_controls", \.setting_show_controls), ("show_timestamps", \.setting_show_timestamps),
    ("artwork_border", \.setting_artwork_border), ("compact_gradient", \.setting_compact_gradient),
    ("waveform", \.setting_waveform), ("clickable_names", \.setting_clickable_names),
    ("position_locked", \.setting_position_locked)
]

// Config mode integers predate the five-mode UI; numeric 1 must remain 3×1.
private let enumNames: [[[String]]] = [
    [["off", "0"], ["subtle", "1"], ["strong", "2"]],
    [["low", "0"], ["normal", "1"], ["high", "2"]],
    [["slow", "0"], ["normal", "1"], ["fast", "2"]],
    [["now_playing", "system", "0"], ["spotify", "1"], ["spotifast", "fastpotify", "2"], ["auto", "3"]],
    [["1x1", "compact", "0"], ["2x1", "two_by_one", "medium"], ["3x1", "expanded", "three_by_one", "wide", "1", "2"], ["1x2", "one_by_two", "3"], ["2x2", "two_by_two", "4"]],
    [["spotify", "0"], ["cat", "pixel_cat", "1"], ["banana_cat", "banana", "2"], ["raccoon", "3"]],
    [["default", "0"], ["cinematic", "1"], ["ripple", "liquid_ripple", "2"], ["flip", "card_flip", "3"], ["vinyl", "vinyl_spin", "4"], ["glitch", "cyber_glitch", "5"]],
    [["small"], ["normal"], ["large"]],
    [["off"], ["active"], ["spotify"], ["spotifast"]]
]
private let enumDefaults: [UInt8] = [1, 1, 1, 0, 2, 1, 1, 1, 0]
private let enumSettings: [(String, WritableKeyPath<WallifyWidgetState, UInt8>, Int)] = [
    ("frame_strength", \.setting_frame, 0), ("glow_intensity", \.setting_intensity, 1),
    ("animation_speed", \.setting_speed, 2), ("media_source", \.setting_source, 3),
    ("widget_mode", \.setting_mode, 4), ("idle_style", \.setting_idle_style, 5),
    ("track_transition", \.setting_transition, 6), ("font_scale", \.setting_font_scale, 7),
    ("media_key_target", \.setting_media_key_target, 8)
]

func parseSettingEnum(_ kind: Int, _ raw: String) -> UInt8 {
    guard enumNames.indices.contains(kind) else { return 0 }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return enumNames[kind].firstIndex(where: { $0.contains(value) }).map(UInt8.init) ?? enumDefaults[kind]
}

@_cdecl("wallify_parse_setting_enum")
public func parseSettingEnumBridge(_ kind: Int32, _ bytes: UnsafePointer<UInt8>?, _ count: Int) -> UInt8 {
    guard count >= 0, count <= 4096, let bytes,
          let raw = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8) else { return 0 }
    return parseSettingEnum(Int(kind), raw)
}

func parseConfiguration(_ content: String, into state: inout WallifyWidgetState) {
    var savedMargins = false
    for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.prefix { $0 != "#" && $0 != ";" }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("[") else { continue }
        let pair = line.split(separator: "=", omittingEmptySubsequences: false)
        guard pair.count >= 2 else { continue }
        let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if let (_, path) = boolSettings.first(where: { $0.0 == key }) {
            switch value.lowercased() {
            case "true", "1", "yes", "on": state[keyPath: path] = true
            case "false", "0", "no", "off": state[keyPath: path] = false
            default: break
            }
        } else if let (_, path, kind) = enumSettings.first(where: { $0.0 == key }) {
            state[keyPath: path] = parseSettingEnum(kind, value)
        } else {
            switch key {
            case "artwork_radius": state.setting_artwork_radius = min(2, UInt8(value) ?? 1)
            case "progress_thickness": state.setting_progress_thickness = min(2, UInt8(value) ?? 1)
            case "widget_grid_x": if let v = UInt8(value) { state.widget_grid_x = min(20, v) }
            case "widget_grid_y": if let v = UInt8(value) { state.widget_grid_y = min(20, v) }
            case "widget_margin_left": if let v = Int32(value) { state.widget_margin_left = max(0, v); savedMargins = true }
            case "widget_margin_top": if let v = Int32(value) { state.widget_margin_top = max(-180, v); savedMargins = true }
            default: break
            }
        }
    }
    if !savedMargins {
        state.widget_margin_left = 8 + Int32(state.widget_grid_x) * 180
        state.widget_margin_top = 8 + Int32(state.widget_grid_y) * 180
    }
}

func configurationValues(_ state: WallifyWidgetState) -> [String: String] {
    var values = Dictionary(uniqueKeysWithValues: boolSettings.map { ($0.0, state[keyPath: $0.1] ? "true" : "false") })
    for (key, path, kind) in enumSettings {
        let index = Int(state[keyPath: path])
        values[key] = enumNames[kind][enumNames[kind].indices.contains(index) ? index : Int(enumDefaults[kind])][0]
    }
    values["artwork_radius"] = String(state.setting_artwork_radius)
    values["progress_thickness"] = String(state.setting_progress_thickness)
    values["widget_margin_left"] = String(state.widget_margin_left)
    values["widget_margin_top"] = String(state.widget_margin_top)
    values["widget_grid_x"] = String(state.widget_grid_x)
    values["widget_grid_y"] = String(state.widget_grid_y)
    return values
}

@_cdecl("wallify_parse_config")
public func parseConfigurationBridge(_ bytes: UnsafePointer<UInt8>?, _ count: Int) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard count >= 0, count <= 1_048_576, let bytes,
          let content = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8) else { return }
    parseConfiguration(content, into: &widgetStatePointer().pointee)
}

@_cdecl("wallify_load_config")
public func loadConfiguration() {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let url = URL(fileURLWithPath: String(cString: wallify_settings_path()))
    do {
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576, let content = String(data: data, encoding: .utf8) else { return }
        parseConfiguration(content, into: &widgetStatePointer().pointee)
    } catch { NSLog("Wallify: settings load failed: %@", error.localizedDescription) }
}

func persistConfiguration(_ content: String, to url: URL) throws {
    try Data(content.utf8).write(to: url, options: .atomic)
}

@_cdecl("wallify_save_config")
public func saveConfiguration() {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    do {
        try persistConfiguration(renderConfiguration(widgetStatePointer().pointee), to: URL(fileURLWithPath: String(cString: wallify_settings_path())))
        refreshSettingsUI()
    } catch { NSLog("Wallify: settings save failed: %@", error.localizedDescription) }
}

@_cdecl("wallify_render_config")
public func renderConfigurationBridge(_ output: UnsafeMutablePointer<UInt8>?, _ capacity: Int) -> Int {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let bytes = Array(renderConfiguration(widgetStatePointer().pointee).utf8)
    guard let output, capacity >= bytes.count else { return -1 }
    output.update(from: bytes, count: bytes.count)
    return bytes.count
}

func renderConfiguration(_ state: WallifyWidgetState) -> String {
    let values = configurationValues(state)
    return """
    # ==============================================================================
    # Wallify Configuration
    #
    # Preferences take effect immediately on reload or when Wallify launches.
    # Settings can also be adjusted via the right-click desktop context menu.
    # ==============================================================================
    
    [Appearance]
    # Ambient glow radiating from album artwork colors [true, false]
    artwork_glow = \(values["artwork_glow"]!)
    native_glass = \(values["native_glass"]!)
    
    # Multi-stop dynamic aurora gradient behind the widget [true, false]
    aurora = \(values["aurora"]!)
    
    # Fluid UI animations for transitions and controls [true, false]
    animations = \(values["animations"]!)
    
    # Live system-audio waveform on the progress bar [true, false]
    waveform = \(values["waveform"]!)

    # Dim album artwork when playback is paused [true, false]
    dim_paused_artwork = \(values["dim_paused_artwork"]!)
    
    # Inner border bezel accentuation [off, subtle, strong]
    frame_strength = \(values["frame_strength"]!)
    
    # Ambient glow radiance [low, normal, high]
    glow_intensity = \(values["glow_intensity"]!)
    
    # Animation pacing and interpolation speed [slow, normal, fast]
    animation_speed = \(values["animation_speed"]!)
    
    [Behavior]
    # Form factor [1x1, 2x1, 3x1, 1x2, 2x2]
    widget_mode = \(values["widget_mode"]!)
    
    # Metadata telemetry source [now_playing, spotify, spotifast]
    media_source = \(values["media_source"]!)
    
    # Mascot shown when player is inactive [cat, banana_cat, raccoon, spotify]
    idle_style = \(values["idle_style"]!)
    
    # Artwork transition on track changes [cinematic, ripple, flip, vinyl, glitch, default]
    track_transition = \(values["track_transition"]!)
    
    # Hide track title and artist text [true, false]
    hide_text = \(values["hide_text"]!)

    # Open track and artist links when clicking their names [true, false]
    clickable_names = \(values["clickable_names"]!)

    # Prevent dragging the widget [true, false]
    position_locked = \(values["position_locked"]!)
    
    # Hide progress/scrubber bar [true, false]
    hide_progress = \(values["hide_progress"]!)
    
    # Show playback controls [true, false]
    show_controls = \(values["show_controls"]!)
    
    # Show elapsed and duration timestamps [true, false]
    show_timestamps = \(values["show_timestamps"]!)
    
    # Show a subtle border around artwork [true, false]
    artwork_border = \(values["artwork_border"]!)
    
    # Show compact-mode gradient underlay [true, false]
    compact_gradient = \(values["compact_gradient"]!)
    
    # Artwork corner radius [0, 1, 2]
    artwork_radius = \(values["artwork_radius"]!)
    
    # Progress bar thickness [0, 1, 2]
    progress_thickness = \(values["progress_thickness"]!)
    
    # Font size scale [small, normal, large]
    font_scale = \(values["font_scale"]!)
    
    # Hardware media key redirect [off, active, spotify, spotifast]
    media_key_target = \(values["media_key_target"]!)
    
    [Position]
    # Screen coordinates in points (from top-left of display below menu bar)
    widget_margin_left = \(values["widget_margin_left"]!)
    widget_margin_top = \(values["widget_margin_top"]!)
    
    # Snap tile coordinates on the 180pt macOS desktop widget grid
    widget_grid_x = \(values["widget_grid_x"]!)
    widget_grid_y = \(values["widget_grid_y"]!)
    
    [Debug]
    # Show developer diagnostics overlay window [true, false]
    widget_debug = \(values["widget_debug"]!)
    
    """ + "\n"
}

@_cdecl("wallify_native_settings_snapshot")
public func widgetSettingsSnapshot(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard let output else { return }
    let state = widgetStatePointer().pointee
    var value = WallifySettingsSnapshot()
    value.native_glass = state.setting_native_glass
    value.glow = state.setting_glow
    value.aurora = state.setting_aurora
    value.animations = state.setting_animations
    value.dim_paused = state.setting_dim
    value.debug_hud = state.setting_debug
    value.margin_left = state.widget_margin_left
    value.margin_top = state.widget_margin_top
    value.grid_x = Int32(state.widget_grid_x)
    value.grid_y = Int32(state.widget_grid_y)
    value.hide_text = state.setting_hide_text
    value.clickable_names = state.setting_clickable_names
    value.position_locked = state.setting_position_locked
    value.hide_progress = state.setting_hide_progress
    value.show_controls = state.setting_show_controls
    value.show_timestamps = state.setting_show_timestamps
    value.artwork_border = state.setting_artwork_border
    value.compact_gradient = state.setting_compact_gradient
    value.waveform = state.setting_waveform
    value.frame_strength = Int32(state.setting_frame)
    value.glow_intensity = Int32(state.setting_intensity)
    value.animation_speed = Int32(state.setting_speed)
    value.media_source = Int32(state.setting_source)
    value.widget_mode = Int32(state.setting_mode)
    value.track_transition = Int32(state.setting_transition)
    value.artwork_radius = Int32(state.setting_artwork_radius)
    value.progress_thickness = Int32(state.setting_progress_thickness)
    value.font_scale = Int32(state.setting_font_scale)
    value.media_key_target = Int32(state.setting_media_key_target)
    value.idle_style = state.setting_idle_style == 1 ? 0 : state.setting_idle_style == 2 ? 1 : state.setting_idle_style == 3 ? 3 : 2
    value.playing = state.global_rate > 0
    withUnsafeMutableBytes(of: &value.title) { destination in
        withUnsafeBytes(of: state.global_title) { destination.copyBytes(from: $0.prefix(min(256, state.global_title_len))) }
    }
    withUnsafeMutableBytes(of: &value.artist) { destination in
        withUnsafeBytes(of: state.global_artist) { destination.copyBytes(from: $0.prefix(min(256, state.global_artist_len))) }
    }
    output.pointee = value
}
