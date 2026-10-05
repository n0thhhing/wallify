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
    state.global_rate = 0; state.play_pause_mix = 0; state.global_anim_art_t = 0
    state.panel_position_dirty = true
    let positionOnly = step(0.31, previous: 0.3)
    precondition(positionOnly.move && !positionOnly.draw)
    state.panel_snap_active = true; state.panel_snap_elapsed = 0; state.panel_save_after_snap = true
    state.panel_snap_start_left = 8; state.panel_snap_target_left = 188; state.panel_snap_start_top = 8; state.panel_snap_target_top = 8
    let snapStep = step(0.1)
    precondition(snapStep.move && !snapStep.draw && snapStep.interval == 1 / 60)
    precondition(state.widget_margin_left > 8 && state.widget_margin_left < 188)
    _ = step(0.2, previous: 0.1)
    let done = step(0.3, previous: 0.2)
    precondition(done.save && !state.panel_snap_active && state.widget_margin_left == 188)
    func simulatedMotion(_ dt: Double, _ count: Int) -> WallifyWidgetState {
        var motion = state
        motion.global_is_dragging = true; motion.global_hover_target = 5
        motion.setting_aurora = true; motion.global_has_artwork = true
        for i in 0..<count {
            _ = advanceAnimations(&motion, now: Double(i + 1) * dt, previous: Double(i) * dt,
                lastDraw: 0, idle: false, compositorActive: false, compositorElapsed: dt, layout: SceneLayout(), titleWidth: 0)
        }
        return motion
    }
    let slow = simulatedMotion(1 / 30, 9), fast = simulatedMotion(1 / 60, 18)
    precondition(abs(slow.seek_expansion - fast.seek_expansion) < 1e-10)
    precondition(abs(slow.hover_amount.0 - fast.hover_amount.0) < 1e-10)
    precondition(abs(slow.aurora_mix - fast.aurora_mix) < 1e-10)
    precondition(slow.seek_expansion > 0 && slow.seek_expansion < 1)
    var returning = slow
    returning.global_is_dragging = false
    var settled = AnimationStep()
    for i in 0..<120 {
        settled = advanceAnimations(&returning, now: Double(i + 1) / 60, previous: Double(i) / 60,
            lastDraw: 0, idle: false, compositorActive: false, compositorElapsed: 1 / 60, layout: SceneLayout(), titleWidth: 0)
        precondition(returning.seek_expansion.isFinite && returning.seek_velocity.isFinite)
    }
    precondition(returning.seek_expansion == 0 && returning.seek_velocity == 0 && settled.interval == 0)
    // Waking from sleep starts with dt == 0; an idle fade still needs another frame.
    for target in [true, false] {
        var waking = returning
        waking.idle_mix = target ? 0 : 1
        let first = advanceAnimations(&waking, now: 10, previous: 10, lastDraw: 10, idle: target,
            compositorActive: true, compositorElapsed: 0, layout: SceneLayout(), titleWidth: 0)
        precondition(first.interval == 1 / 60)
        _ = advanceAnimations(&waking, now: 10.1, previous: 10, lastDraw: 10, idle: target,
            compositorActive: true, compositorElapsed: 0.1, layout: SceneLayout(), titleWidth: 0)
        precondition(waking.idle_mix > 0 && waking.idle_mix < 1)
    }
    var nativePhase = state
    nativePhase.cat_time = 1
    _ = advanceAnimations(&nativePhase, now: 10, previous: 10, lastDraw: 10, idle: false,
        compositorActive: true, compositorElapsed: 12, layout: SceneLayout(), titleWidth: 0)
    precondition(nativePhase.cat_time == 13)
    var resize = state
    resize.mode_transition_active = true; resize.mode_mix = 0; resize.mode_from = 0; resize.setting_mode = 2
    resize.mode_start_width = 180; resize.mode_start_height = 180
    resize.mode_target_width = 540; resize.mode_target_height = 180
    _ = advanceAnimations(&resize, now: 1, previous: 1, lastDraw: 1, idle: false,
        compositorActive: false, compositorElapsed: 0, layout: SceneLayout(), titleWidth: 0)
    precondition(resize.mode_transition_active && resize.mode_mix == 0)
    let resized = advanceAnimations(&resize, now: 1.05, previous: 1, lastDraw: 1, idle: false,
        compositorActive: false, compositorElapsed: 0.05, layout: SceneLayout(), titleWidth: 0)
    var interpolated = SceneLayout()
    interpolated.update(width: Double(resized.resize!.0), height: Double(resized.resize!.1), state: resize)
    precondition(abs(interpolated.geometry.compact_mix - (1 - smoothTransition(resize.mode_mix))) < 1e-10)
    precondition(smoothTransition(0) == 0 && smoothTransition(1) == 1 && smoothTransition(0.5) == 0.5)
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
