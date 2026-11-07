import Foundation

// Every user setting, described once. Config parsing and writing, apply, restore defaults,
// the settings snapshot and the menus all read this table; a new setting is one entry here
// plus its state field.
struct SettingSpec {
    enum Storage {
        case bool(WritableKeyPath<WallifyWidgetState, Bool>, WritableKeyPath<WallifySettingsSnapshot, Bool>)
        case choice(WritableKeyPath<WallifyWidgetState, UInt8>, WritableKeyPath<WallifySettingsSnapshot, Int32>)
    }
    let key: Int32
    let name: String          // config file key
    let title: String         // UI title
    let storage: Storage
    var values: [[String]] = []  // config spellings per stored value; the first is written
    var labels: [String] = []    // UI labels per public value
    var stored: [UInt8]? = nil   // public value -> stored value, where they differ
    var defaultValue: UInt8 = 0  // stored value; 1 = on for bools

    func storedValue(_ value: Int) -> UInt8 {
        let clamped = max(0, min(labels.count - 1, value))
        return stored?[clamped] ?? UInt8(clamped)
    }
    func publicValue(_ value: UInt8) -> Int32 { Int32(stored?.firstIndex(of: value) ?? Int(value)) }
}

private func toggle(_ key: Int32, _ name: String, _ title: String, _ path: WritableKeyPath<WallifyWidgetState, Bool>,
                    _ snapshot: WritableKeyPath<WallifySettingsSnapshot, Bool>, on: Bool) -> SettingSpec {
    SettingSpec(key: key, name: name, title: title, storage: .bool(path, snapshot), defaultValue: on ? 1 : 0)
}

private func choice(_ key: Int32, _ name: String, _ title: String, _ path: WritableKeyPath<WallifyWidgetState, UInt8>,
                    _ snapshot: WritableKeyPath<WallifySettingsSnapshot, Int32>, _ labels: [String], _ values: [[String]],
                    stored: [UInt8]? = nil, default value: UInt8) -> SettingSpec {
    SettingSpec(key: key, name: name, title: title, storage: .choice(path, snapshot), values: values, labels: labels,
                stored: stored, defaultValue: value)
}

let settingSpecs: [SettingSpec] = [
    toggle(0, "artwork_glow", "Artwork Glow", \.setting_glow, \.glow, on: true),
    toggle(1, "aurora", "Aurora", \.setting_aurora, \.aurora, on: true),
    toggle(2, "animations", "Animations", \.setting_animations, \.animations, on: true),
    toggle(3, "dim_paused_artwork", "Dim Artwork When Paused", \.setting_dim, \.dim_paused, on: true),
    toggle(4, "widget_debug", "Debug Console", \.setting_debug, \.debug_hud, on: false),
    toggle(5, "native_glass", "Native Glass", \.setting_native_glass, \.native_glass, on: false),
    toggle(6, "hide_text", "Hide Track Text", \.setting_hide_text, \.hide_text, on: false),
    toggle(7, "hide_progress", "Hide Progress Bar", \.setting_hide_progress, \.hide_progress, on: false),
    toggle(8, "show_controls", "Playback Controls", \.setting_show_controls, \.show_controls, on: true),
    toggle(9, "show_timestamps", "Time Labels", \.setting_show_timestamps, \.show_timestamps, on: true),
    toggle(19, "artwork_border", "Artwork Border", \.setting_artwork_border, \.artwork_border, on: true),
    toggle(20, "compact_gradient", "Compact Contrast", \.setting_compact_gradient, \.compact_gradient, on: true),
    toggle(23, "waveform", "System Audio Waveform", \.setting_waveform, \.waveform, on: false),
    toggle(24, "clickable_names", "Clickable Names", \.setting_clickable_names, \.clickable_names, on: false),
    toggle(25, "position_locked", "Lock Position", \.setting_position_locked, \.position_locked, on: false),
    toggle(28, "lyrics", "Synced Lyrics", \.setting_lyrics, \.lyrics, on: false),
    toggle(29, "check_updates", "Check for Updates", \.setting_check_updates, \.check_updates, on: true),
    choice(10, "frame_strength", "Custom Border", \.setting_frame, \.frame_strength, ["Off", "Subtle", "Strong"],
           [["off", "0"], ["subtle", "1"], ["strong", "2"]], default: 1),
    choice(11, "glow_intensity", "Glow Intensity", \.setting_intensity, \.glow_intensity, ["Low", "Normal", "High"],
           [["low", "0"], ["normal", "1"], ["high", "2"]], default: 1),
    choice(12, "animation_speed", "Animation Speed", \.setting_speed, \.animation_speed, ["Slow", "Normal", "Fast"],
           [["slow", "0"], ["normal", "1"], ["fast", "2"]], default: 1),
    choice(13, "media_source", "Media Source", \.setting_source, \.media_source, ["Now Playing", "Spotify", "Spotifast", "Auto"],
           [["now_playing", "system", "0"], ["spotify", "1"], ["spotifast", "fastpotify", "2"], ["auto", "3"]], default: 0),
    // Config mode integers predate the five-mode UI; numeric 1 must remain 3×1.
    choice(14, "widget_mode", "Widget Size", \.setting_mode, \.widget_mode, ["1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"],
           [["1x1", "compact", "0"], ["2x1", "two_by_one", "medium"], ["3x1", "expanded", "three_by_one", "wide", "1", "2"],
            ["1x2", "one_by_two", "3"], ["2x2", "two_by_two", "4"]], default: 2),
    // Stored values predate the menu order: 0 is the Spotify launcher, 1 the pixel cat.
    choice(15, "idle_style", "Companion", \.setting_idle_style, \.idle_style, ["Pixel Cat", "Banana Cat", "Spotify Launcher", "Raccoon"],
           [["spotify", "0"], ["cat", "pixel_cat", "1"], ["banana_cat", "banana", "2"], ["raccoon", "3"]], stored: [1, 2, 0, 3], default: 1),
    choice(16, "track_transition", "Track Transition", \.setting_transition, \.track_transition,
           ["Default", "Cinematic", "Ripple", "Card Flip", "Vinyl", "Glitch"],
           [["default", "0"], ["cinematic", "1"], ["ripple", "liquid_ripple", "2"], ["flip", "card_flip", "3"],
            ["vinyl", "vinyl_spin", "4"], ["glitch", "cyber_glitch", "5"]], default: 1),
    choice(17, "font_scale", "Font Size", \.setting_font_scale, \.font_scale, ["Small", "Normal", "Large"],
           [["small"], ["normal"], ["large"]], default: 1),
    choice(18, "media_key_target", "Media Key Target", \.setting_media_key_target, \.media_key_target,
           ["Off", "Active", "Spotify", "Spotifast"], [["off"], ["active"], ["spotify"], ["spotifast"]], default: 0),
    choice(21, "artwork_radius", "Artwork Corners", \.setting_artwork_radius, \.artwork_radius, ["Soft", "Rounded", "Large"],
           [["0"], ["1"], ["2"]], default: 1),
    choice(22, "progress_thickness", "Progress Thickness", \.setting_progress_thickness, \.progress_thickness,
           ["Thin", "Standard", "Thick"], [["0"], ["1"], ["2"]], default: 1),
    choice(26, "stopped_behavior", "When Music Stops", \.setting_stopped_behavior, \.stopped_behavior,
           ["Show Companion", "Keep Last Track", "Hide Widget"], [["companion", "0"], ["keep_last_track", "keep", "1"], ["hide", "2"]], default: 0),
    choice(27, "scroll_action", "Scroll Action", \.setting_scroll_action, \.scroll_action, ["Off", "Volume", "Seek"],
           [["off"], ["volume"], ["seek"]], default: 0)
]

private let specsByKey = Dictionary(uniqueKeysWithValues: settingSpecs.map { ($0.key, $0) })
private let specsByName = Dictionary(uniqueKeysWithValues: settingSpecs.map { ($0.name, $0) })
func settingSpec(_ key: Int32) -> SettingSpec? { specsByKey[key] }

@_cdecl("wallify_native_apply_bool")
public func applyWidgetBool(_ key: Int32, _ value: Bool) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard case .bool(let path, _)? = specsByKey[key]?.storage else { return }
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

// `value` is the public value, the index into the setting's labels.
@_cdecl("wallify_native_apply_int")
public func applyWidgetInt(_ key: Int32, _ value: Int32) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard let spec = specsByKey[key], case .choice(let path, _) = spec.storage else { return }
    let state = widgetStatePointer(), stored = spec.storedValue(Int(value))
    if key == 14 {
        guard !state.pointee.setting_position_locked else { return }
        if state.pointee.setting_mode != stored {
            beginWidgetMode(stored, Double(wallify_width()), Double(wallify_height()), state.pointee.setting_animations)
            if !state.pointee.mode_transition_active {
                let (w, h) = modeDimensions(stored)
                resizeMetalWidget(Int32(w), Int32(h))
            }
        }
    } else {
        state.pointee[keyPath: path] = stored
    }
    if key == 18 { updateMediaKeyTap(Int32(stored)) }
    if key == 26 { refreshStoppedPresentation() }
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
    for spec in settingSpecs where spec.key != 14 {  // the size changes through its animated transition below
        switch spec.storage {
        case .bool(let path, _): state.pointee[keyPath: path] = spec.defaultValue != 0
        case .choice(let path, _): state.pointee[keyPath: path] = spec.defaultValue
        }
    }
    refreshStoppedPresentation()
    audioWaveform.update(active: false)
    beginWidgetMode(specsByKey[14]!.defaultValue, Double(wallify_width()), Double(wallify_height()), true)
    widget_debug_window_hide()
    updateMediaKeyTap(Int32(specsByKey[18]!.defaultValue))
    saveConfiguration()
    requestWidgetFrame()
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
        if let spec = specsByName[key] {
            switch spec.storage {
            case .bool(let path, _):
                // An unrecognised boolean keeps the current value.
                switch value.lowercased() {
                case "true", "1", "yes", "on": state[keyPath: path] = true
                case "false", "0", "no", "off": state[keyPath: path] = false
                default: break
                }
            case .choice(let path, _):
                // An unrecognised choice falls back to the default.
                state[keyPath: path] = spec.values.firstIndex { $0.contains(value.lowercased()) }.map(UInt8.init) ?? spec.defaultValue
            }
        } else {
            switch key {
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
    var values = [String: String]()
    for spec in settingSpecs {
        switch spec.storage {
        case .bool(let path, _): values[spec.name] = state[keyPath: path] ? "true" : "false"
        case .choice(let path, _):
            let index = Int(state[keyPath: path])
            values[spec.name] = spec.values[spec.values.indices.contains(index) ? index : Int(spec.defaultValue)][0]
        }
    }
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
        DispatchQueue.main.async { rememberWidgetDisplayPlacement() }
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
    let documented = """
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

    # When music stops (paused tracks remain visible) [companion, keep_last_track, hide]
    stopped_behavior = \(values["stopped_behavior"]!)
    
    # Artwork transition on track changes [cinematic, ripple, flip, vinyl, glitch, default]
    track_transition = \(values["track_transition"]!)
    
    # Hide track title and artist text [true, false]
    hide_text = \(values["hide_text"]!)

    # Open track and artist links when clicking their names [true, false]
    clickable_names = \(values["clickable_names"]!)

    # Synced lyrics under the progress bar, from lrclib.net (sends title and artist) [true, false]
    lyrics = \(values["lyrics"]!)

    # Scrolling on the widget changes the volume or seeks [off, volume, seek]
    scroll_action = \(values["scroll_action"]!)

    # Prevent dragging and resizing the widget [true, false]
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
    
    [Updates]
    # Check GitHub daily for a newer Wallify release [true, false]
    check_updates = \(values["check_updates"]!)

    [Debug]
    # Show developer diagnostics overlay window [true, false]
    widget_debug = \(values["widget_debug"]!)
    
    """ + "\n"
    // Settings added to the table but not yet documented above are still saved.
    let undocumented = settingSpecs.filter { !documented.contains("\n\($0.name) = ") }
    return undocumented.isEmpty ? documented : documented + "[Other]\n" + undocumented.map { "\($0.name) = \(values[$0.name]!)\n" }.joined()
}

@_cdecl("wallify_native_settings_snapshot")
public func widgetSettingsSnapshot(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    guard let output else { return }
    let state = widgetStatePointer().pointee
    var value = WallifySettingsSnapshot()
    for spec in settingSpecs {
        switch spec.storage {
        case .bool(let path, let field): value[keyPath: field] = state[keyPath: path]
        case .choice(let path, let field): value[keyPath: field] = spec.publicValue(state[keyPath: path])
        }
    }
    value.margin_left = state.widget_margin_left
    value.margin_top = state.widget_margin_top
    value.grid_x = Int32(state.widget_grid_x)
    value.grid_y = Int32(state.widget_grid_y)
    value.playing = state.global_rate > 0
    withUnsafeMutableBytes(of: &value.title) { destination in
        withUnsafeBytes(of: state.global_title) { destination.copyBytes(from: $0.prefix(min(256, state.global_title_len))) }
    }
    withUnsafeMutableBytes(of: &value.artist) { destination in
        withUnsafeBytes(of: state.global_artist) { destination.copyBytes(from: $0.prefix(min(256, state.global_artist_len))) }
    }
    output.pointee = value
}
