import Foundation

private let widgetState: UnsafeMutablePointer<WallifyWidgetState> = {
    let pointer = UnsafeMutablePointer<WallifyWidgetState>.allocate(capacity: 1)
    var value = WallifyWidgetState()
    value.global_title_len = 0
    value.global_artist_len = 0
    value.global_has_artwork = false
    value.global_rate_lock = 0
    value.global_rate_lock_until = 0
    value.playback_state.pending = -1
    value.playback_state.confirmed_since = -1
    value.extracted_r = 180
    value.extracted_g = 180
    value.extracted_b = 180
    value.global_is_dragging = false
    value.global_rate = 0.0
    value.global_duration = 0.0
    value.global_position = 0.0
    value.global_elapsed = 0.0
    value.global_track_id_len = 0
    value.previous_track_id_len = 0
    value.global_art_crossfade_alpha = 1.0
    value.global_anim_art_t = 0.0
    value.play_pause_mix = 0.0
    value.seek_expansion = 0.0
    value.seek_velocity = 0.0
    value.aurora_mix = 0.0
    value.setting_hide_text = false
    value.setting_hide_progress = false
    value.setting_show_controls = true
    value.setting_show_timestamps = true
    value.setting_artwork_border = true
    value.setting_compact_gradient = true
    value.setting_font_scale = 1
    value.setting_artwork_radius = 1
    value.setting_progress_thickness = 1
    value.setting_media_key_target = 0
    value.setting_glow = true
    value.setting_native_glass = false
    value.setting_aurora = true
    value.setting_animations = true
    value.setting_dim = true
    value.setting_frame = 1
    value.setting_intensity = 1
    value.setting_speed = 1
    value.setting_idle_style = 1
    value.setting_transition = 1
    value.setting_source = 0
    value.setting_debug = false
    value.idle_mix = 0.0
    value.cat_pet_until = 0.0
    value.cat_time = 0.0
    value.pointer_x = 90
    value.pointer_y = 90
    value.setting_mode = 2
    value.mode_from = 2
    value.mode_mix = 1.0
    value.mode_transition_active = false
    value.mode_start_width = 540
    value.mode_start_height = 180
    value.mode_target_width = 540
    value.mode_target_height = 180
    value.animation_time = 0
    value.marquee_offset = 0
    value.marquee_direction = 1
    value.widget_grid_x = 0
    value.widget_grid_y = 0
    value.global_panel_dragging = false
    value.widget_drag_start_mouse_x = 0
    value.widget_drag_start_mouse_y = 0
    value.widget_drag_start_margin_left = 8
    value.widget_drag_start_margin_top = 8
    value.widget_margin_left = 8
    value.widget_margin_top = 8
    value.panel_position_dirty = false
    value.panel_snap_active = false
    value.panel_snap_elapsed = 0
    value.panel_snap_start_left = 0
    value.panel_snap_start_top = 0
    value.panel_snap_target_left = 0
    value.panel_snap_target_top = 0
    value.panel_save_after_snap = false
    value.global_hover_target = 0
    value.global_click_target = 0
    value.artwork_refresh_pending = true
    value.art_transition_until = 0
    pointer.initialize(to: value)
    return pointer
}()

@_cdecl("wallify_widget_state")
public func sharedWidgetState() -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(widgetState) }

@_cdecl("wallify_widget_state_size")
public func widgetStateSize() -> Int { MemoryLayout<WallifyWidgetState>.size }

func widgetStatePointer() -> UnsafeMutablePointer<WallifyWidgetState> { widgetState }
