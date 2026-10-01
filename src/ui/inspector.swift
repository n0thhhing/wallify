import AppKit

@MainActor
final class DesktopInteraction {
    static let shared = DesktopInteraction()
    var offsetX: Double = 0, offsetY: Double = 33
    var hasOffsets = false
    var outline = WallifyWindowRect()
    var candidateCount: UInt32 = 0
    var distance: Double = 0
    var modeMix: Double = 0
    var width: Double = 164, height: Double = 164
    var dragging = false

    func startDrag(left: Int32, top: Int32) {
        var x: Double = 0, y: Double = 0
        if widgetPanelOffsets(&x, &y) { offsetX = x; offsetY = y; hasOffsets = true; return }
        var info = WallifyWindowInfo(); queryPlayerWindow(&info)
        if info.number > 0 && info.frame.width > 0 && info.frame.height > 0 {
            offsetX = info.frame.x - Double(left); offsetY = info.frame.y - Double(top); hasOffsets = true
        }
    }
    func nearby(left: Int32, top: Int32, x: Double, y: Double, width: Double, height: Double) -> WallifyPanelSnap {
        var candidates = [WallifyWindowRect](repeating: WallifyWindowRect(), count: 64)
        let count = candidates.withUnsafeMutableBufferPointer { copyDesktopCandidates($0.baseAddress, UInt($0.count)) }
        candidateCount = UInt32(count)
        let ox = hasOffsets ? offsetX : 0, oy = hasOffsets ? offsetY : 0
        var result = WallifyPanelSnap()
        candidates.withUnsafeBufferPointer { calculatePanelSnap($0.baseAddress, count, ox + Double(left) + x, oy + Double(top) + y, width, height, ox, oy, x, y, &result) }
        distance = result.distance_sq
        return result
    }
}

func showInspector() {
    #if DEBUG_INSPECTOR
    DispatchQueue.main.async { wallify_imgui_inspector_show() }
    #else
    NSLog("Wallify: Inspector is available in a Debug Inspector build")
    #endif
}

func hideInspector() {
    #if DEBUG_INSPECTOR
    DispatchQueue.main.async { wallify_imgui_inspector_hide() }
    #endif
}

@MainActor func inspectorSnapshot() -> WallifyDebugSnapshot {
    var player = WallifyWindowInfo(); queryPlayerWindow(&player)
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let state = widgetStatePointer().pointee, layout = sceneLayout, desktop = DesktopInteraction.shared
    var result = WallifyDebugSnapshot()
    let boolFields: [(WritableKeyPath<WallifyDebugSnapshot, Int32>, Bool)] = [
        (\.glow, state.setting_glow), (\.aurora, state.setting_aurora), (\.animations, state.setting_animations),
        (\.dim, state.setting_dim), (\.native_glass, state.setting_native_glass), (\.hide_text, state.setting_hide_text),
        (\.hide_progress, state.setting_hide_progress), (\.show_controls, state.setting_show_controls),
        (\.timestamps, state.setting_show_timestamps), (\.artwork_border, state.setting_artwork_border), (\.compact_gradient, state.setting_compact_gradient),
        (\.dragging, desktop.dragging), (\.seeking, state.global_is_dragging), (\.panel_dragging, state.global_panel_dragging),
        (\.transition_active, state.mode_transition_active), (\.frame_requested, stateFlag(2, 0, false)),
        (\.has_artwork, state.global_has_artwork), (\.snap_active, state.panel_snap_active)
    ]
    for (path, value) in boolFields { result[keyPath: path] = value ? 1 : 0 }
    let enums: [(WritableKeyPath<WallifyDebugSnapshot, Int32>, UInt8)] = [
        (\.frame, state.setting_frame), (\.intensity, state.setting_intensity), (\.speed, state.setting_speed),
        (\.source, state.setting_source), (\.mode, state.setting_mode), (\.transition, state.setting_transition),
        (\.font_scale, state.setting_font_scale), (\.media_key_target, state.setting_media_key_target),
        (\.artwork_radius, state.setting_artwork_radius), (\.progress_thickness, state.setting_progress_thickness)
    ]
    for (path, value) in enums { result[keyPath: path] = Int32(value) }
    result.width = metalWidgetWidth(); result.height = metalWidgetHeight()
    result.margin_left = state.widget_margin_left; result.margin_top = state.widget_margin_top
    result.window_number = player.number; result.window_layer = player.layer
    result.window_x = player.frame.x; result.window_y = player.frame.y; result.window_width = player.frame.width; result.window_height = player.frame.height
    result.outline_x = desktop.outline.x; result.outline_y = desktop.outline.y; result.outline_width = desktop.outline.width; result.outline_height = desktop.outline.height
    result.candidate_count = desktop.candidateCount; result.snap_distance_sq = desktop.distance; result.mode_mix = Float(desktop.modeMix)
    result.title_len = UInt32(min(255, state.global_title_len)); result.artist_len = UInt32(min(255, state.global_artist_len))
    withUnsafeMutableBytes(of: &result.title) { dest in withUnsafeBytes(of: state.global_title) { dest.copyBytes(from: $0.prefix(Int(result.title_len))) } }
    withUnsafeMutableBytes(of: &result.artist) { dest in withUnsafeBytes(of: state.global_artist) { dest.copyBytes(from: $0.prefix(Int(result.artist_len))) } }
    result.pointer_x = state.pointer_x; result.pointer_y = state.pointer_y
    result.hover_target = state.global_hover_target; result.click_target = state.global_click_target
    result.layout_width = layout.width; result.layout_height = layout.height; result.compact_mix = layout.geometry.compact_mix; result.transition_mix = state.mode_mix
    result.idle_mix = state.idle_mix; result.aurora_mix = state.aurora_mix; result.artwork_mix = Double(state.global_art_crossfade_alpha)
    result.play_pause_mix = state.play_pause_mix; result.position = state.global_position; result.duration = state.global_duration; result.rate = state.global_rate
    let input = layout.inputGeometry(state), g = layout.geometry
    let rects = [layout.card, cardRect(g.art_x, g.art_y, g.art_size, g.art_size, g.art_radius), cardRect(g.bar_x, g.bar_y, g.bar_w, g.bar_h), input.bar, input.buttons.0, input.buttons.1, input.buttons.2]
    let values = rects.flatMap { [$0.x, $0.y, $0.w, $0.h, $0.radius] }
    withUnsafeMutableBytes(of: &result.geometry) { destination in values.withUnsafeBytes { destination.copyBytes(from: $0) } }
    let controls: UInt32 = layout.controlsVisible(state.setting_show_controls) && !spotifyIsIdle() ? 1 : 0
    let progress: UInt32 = layout.progressVisible(state.setting_hide_progress) && !spotifyIsIdle() ? 1 : 0
    result.geometry_visible = (1, spotifyIsIdle() ? 0 : 1, progress, progress, controls, controls, controls)
    return result
}

@MainActor func applyInspectorInt(_ key: Int32, _ value: Int32) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    let state = widgetStatePointer(), desktop = DesktopInteraction.shared
    switch key {
    case 1000: desktop.modeMix = min(1, max(0, Double(value) / 100))
    case 1001: desktop.width = max(1, Double(value)); resizeMetalWidget(Int32(desktop.width), metalWidgetHeight())
    case 1002: desktop.height = max(1, Double(value)); resizeMetalWidget(metalWidgetWidth(), Int32(desktop.height))
    case 1003: state.pointee.widget_margin_left = value; state.pointee.panel_position_dirty = true; moveWidgetPanel(value, state.pointee.widget_margin_top)
    case 1004: state.pointee.widget_margin_top = value; state.pointee.panel_position_dirty = true; moveWidgetPanel(state.pointee.widget_margin_left, value)
    case 1005: desktop.outline.x = Double(value)
    case 1006: desktop.outline.y = Double(value)
    case 1007: desktop.outline.width = max(1, Double(value))
    case 1008: desktop.outline.height = max(1, Double(value))
    default: applyWidgetInt(key, value); return
    }
    saveConfiguration(); requestWidgetFrame()
}
