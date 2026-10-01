import Foundation

func checkAnimationCoordination() {
    precondition(playbackFrameInterval(playing: true, dragging: false, playerVisible: true, progressVisible: true, timestampsVisible: true) == 1 / 20)
    precondition(playbackFrameInterval(playing: true, dragging: false, playerVisible: true, progressVisible: false, timestampsVisible: true) == 1)
    precondition(playbackFrameInterval(playing: true, dragging: false, playerVisible: true, progressVisible: false, timestampsVisible: false) == 0)
    precondition(playbackFrameInterval(playing: true, dragging: true, playerVisible: true, progressVisible: true, timestampsVisible: true) == 0)
    var state = widgetStatePointer().pointee
    state.global_rate = 1; state.play_pause_mix = 1; state.global_anim_art_t = 1
    state.idle_mix = 0; state.global_is_dragging = false; state.global_hover_target = 0; state.hover_amount = (0, 0, 0)
    state.seek_expansion = 0; state.seek_velocity = 0; state.setting_native_glass = false; state.setting_aurora = false
    state.aurora_mix = 0; state.art_transition_until = 0; state.mode_transition_active = false
    state.panel_position_dirty = false; state.panel_snap_active = false; state.setting_animations = true
    func step(_ now: Double, previous: Double = 0, active: Bool = false) -> AnimationStep {
        advanceAnimations(&state, now: now, previous: previous, lastDraw: 0, idle: false, compositorActive: active, compositorElapsed: now - previous, layout: SceneLayout(), titleWidth: 0)
    }
    precondition(step(0.1).interval == 1 / 20)
    state.global_rate = 0
    precondition(step(0.2, previous: 0.1).draw && state.global_anim_art_t > 0 && state.global_anim_art_t < 1)
    let fading = state.global_anim_art_t
    state.global_rate = 1
    _ = step(0.23, previous: 0.2)
    precondition(state.global_anim_art_t > fading && state.global_anim_art_t < 1)
    state.setting_animations = false
    _ = step(0.24, previous: 0.23)
    precondition(state.global_anim_art_t == 1)
    state.setting_animations = true
    state.global_is_dragging = true
    precondition(step(0.2, previous: 0.1).interval == 1 / 60 && state.seek_expansion > 0)
    state.setting_animations = false
    _ = step(0.3, previous: 0.2)
    precondition(state.seek_expansion == 1 && state.seek_velocity == 0)
    state.global_is_dragging = false; state.setting_animations = true; state.seek_expansion = 0
    state.panel_snap_active = true; state.panel_snap_elapsed = 0; state.panel_save_after_snap = true
    state.panel_snap_start_left = 8; state.panel_snap_target_left = 188; state.panel_snap_start_top = 8; state.panel_snap_target_top = 8
    _ = step(0.1)
    precondition(state.widget_margin_left > 8 && state.widget_margin_left < 188)
    _ = step(0.2, previous: 0.1)
    let done = step(0.3, previous: 0.2)
    precondition(done.save && !state.panel_snap_active && state.widget_margin_left == 188)
    state.idle_mix = 1; state.setting_idle_style = 1; state.global_panel_dragging = false
    state.cat_pet_until = 0; state.mode_transition_active = false
    precondition(idleCompositorEligible(state))
    state.setting_animations = false
    precondition(!idleCompositorEligible(state))
    enqueueContextSelection(83)
    precondition(takeContextSelection() == 83 && takeContextSelection() == 0)
    var keyState = state
    let layout = SceneLayout(), first = StaticSceneKey(layout: layout, state: keyState, hasArtwork: true, generation: 1)
    keyState.animation_time += 1
    precondition(first == StaticSceneKey(layout: layout, state: keyState, hasArtwork: true, generation: 1))
    precondition(first != StaticSceneKey(layout: layout, state: keyState, hasArtwork: true, generation: 2))
}
