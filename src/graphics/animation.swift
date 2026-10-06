import Foundation

func playbackFrameInterval(playing: Bool, dragging: Bool, playerVisible: Bool, progressVisible: Bool, timestampsVisible: Bool) -> Double {
    guard playing, !dragging, playerVisible else { return 0 }
    return progressVisible ? 1 / 20 : timestampsVisible ? 1 : 0
}

struct AnimationStep {
    var draw = false
    var interval: Double = 0
    var resize: (Int32, Int32)?
    var move = false
    var save = false
}

func advanceAnimations(_ state: inout WallifyWidgetState, now: Double, previous: Double, lastDraw: Double,
                       idle: Bool, compositorActive: Bool, compositorElapsed: Double, layout: SceneLayout, titleWidth: Double,
                       waveformAvailable: Bool = false) -> AnimationStep {
    var result = AnimationStep(), high = false, visual = false, ambient = false
    var idleInterval: Double = 0
    if state.animation_time < state.art_transition_until { result.draw = true; visual = true }
    if !state.setting_animations {
        state.play_pause_mix = state.global_rate > 0 ? 1 : 0
        state.global_anim_art_t = state.play_pause_mix; state.art_transition_until = 0
        state.seek_expansion = state.global_is_dragging ? 1 : 0; state.seek_velocity = 0
    }
    let dt = min(0.1, max(0, now - previous)) * animationSpeed(state.setting_speed)
    state.animation_time += dt
    let waveformTarget: Double = state.setting_waveform && state.setting_animations && state.global_rate > 0 &&
        state.global_duration > 0 && !idle && layout.progressVisible(state.setting_hide_progress) && waveformAvailable ? 1 : 0
    let oldWaveform = state.waveform_mix
    state.waveform_mix = state.setting_animations ? oldWaveform + min(dt * 4, max(-dt * 4, waveformTarget - oldWaveform)) : waveformTarget
    if oldWaveform != state.waveform_mix { result.draw = true }
    if state.waveform_mix != waveformTarget { visual = state.setting_animations }
    let idleTarget: Double = idle ? 1 : 0, oldIdle = state.idle_mix
    state.idle_mix = state.setting_animations ? oldIdle + min(dt * 2.5, max(-dt * 2.5, idleTarget - oldIdle)) : idleTarget
    if oldIdle != state.idle_mix { result.draw = true }
    if state.idle_mix != idleTarget { high = state.setting_animations }
    if state.idle_mix > 0 && state.cat_pet_until > 0 && state.animation_time < state.cat_pet_until + 0.1 { result.draw = true }
    if compositorActive { state.cat_time += compositorElapsed }
    if state.idle_mix > 0 && state.setting_idle_style != 0 && state.setting_animations {
        let fps: Double = state.setting_idle_style == 2 ? 24 : 30, tick = floor(state.cat_time * fps)
        idleInterval = 1 / fps
        if !compositorActive { state.cat_time += dt }
        if floor(state.cat_time * fps) != tick { result.draw = true }
    }
    if state.mode_transition_active {
        high = true; result.draw = true
        if !state.setting_animations {
            let (w, h) = modeDimensions(state.setting_mode)
            result.resize = (Int32(w), Int32(h))
            finishModeState(&state)
        } else {
            state.mode_mix = min(1, state.mode_mix + dt * 5.5)
            let eased = smoothTransition(state.mode_mix)
            result.resize = (Int32(max(1, (state.mode_start_width + (state.mode_target_width - state.mode_start_width) * eased).rounded())),
                             Int32(max(1, (state.mode_start_height + (state.mode_target_height - state.mode_start_height) * eased).rounded())))
            if state.mode_mix >= 1 {
                finishModeState(&state)
                let (w, h) = modeDimensions(state.setting_mode); result.resize = (Int32(w), Int32(h))
            }
        }
    }
    if state.panel_position_dirty { state.panel_position_dirty = false; result.move = true }
    if state.panel_snap_active {
        high = true; state.panel_snap_elapsed += dt
        let t = min(1, state.panel_snap_elapsed / 0.22), eased = smoothTransition(t)
        state.widget_margin_left = Int32((Double(state.panel_snap_start_left) + (Double(state.panel_snap_target_left) - Double(state.panel_snap_start_left)) * eased).rounded())
        state.widget_margin_top = Int32((Double(state.panel_snap_start_top) + (Double(state.panel_snap_target_top) - Double(state.panel_snap_start_top)) * eased).rounded())
        result.move = true
        if t >= 1 { state.panel_snap_active = false; result.save = state.panel_save_after_snap; state.panel_save_after_snap = false }
    }
    if !state.setting_hide_text && !idle && layout.geometry.compact_mix > 0.01 && state.global_title_len > 0 && titleWidth > 126 && state.setting_animations {
        let travel = titleWidth - 126
        state.marquee_offset += dt * 28 * state.marquee_direction
        if state.marquee_offset >= travel { state.marquee_offset = travel; state.marquee_direction = -1 }
        else if state.marquee_offset <= 0 { state.marquee_offset = 0; state.marquee_direction = 1 }
        result.draw = true; visual = true
    } else { state.marquee_offset = 0; state.marquee_direction = 1 }
    let nativeGlass = state.setting_native_glass && !terminalMode
    let auroraTarget: Double = !nativeGlass && state.setting_aurora && state.idle_mix < 0.5 && state.global_has_artwork ? 1 : 0
    if !state.setting_animations || nativeGlass { state.aurora_mix = auroraTarget }
    else if abs(state.aurora_mix - auroraTarget) > 0.001 {
        state.aurora_mix += (auroraTarget - state.aurora_mix) * (1 - exp(-dt * 3.5)); result.draw = true; ambient = true
    } else { state.aurora_mix = auroraTarget }
    if state.aurora_mix > 0.001 && state.global_rate > 0 && state.setting_animations { result.draw = true; ambient = true }
    let seekTarget: Double = state.global_is_dragging ? 1 : 0
    if abs(state.seek_expansion - seekTarget) > 0.0001 || abs(state.seek_velocity) > 0.001 {
        high = true
        // Solve the critically damped spring for the entire time step instead of
        // nudging velocity with Euler integration. This keeps the seek bar stable
        // when the scheduler changes frame rate or a frame arrives late. The 18
        // is the spring's response rate, and momentum combines its current speed
        // with displacement from the target. Snap both values at the threshold:
        // an almost-settled spring should not keep requesting 60 FPS forever.
        let displacement = state.seek_expansion - seekTarget, decay = exp(-18 * dt)
        let momentum = state.seek_velocity + 18 * displacement
        state.seek_expansion = seekTarget + (displacement + momentum * dt) * decay
        state.seek_velocity = (state.seek_velocity - 18 * momentum * dt) * decay
        if abs(state.seek_expansion - seekTarget) < 0.0001 && abs(state.seek_velocity) < 0.001 {
            state.seek_expansion = seekTarget; state.seek_velocity = 0
        }
        result.draw = true
    }
    let playback = playbackFrameInterval(playing: state.global_rate > 0, dragging: state.global_is_dragging, playerVisible: state.idle_mix < 1,
        progressVisible: layout.progressVisible(state.setting_hide_progress), timestampsVisible: !state.setting_hide_text && state.setting_show_timestamps && layout.geometry.compact_mix <= 0.12)
    if playback > 0 && !high && now - lastDraw >= playback { result.draw = true }
    let iconTarget: Double = state.global_rate > 0 ? 1 : 0
    if state.play_pause_mix != iconTarget {
        visual = true; state.play_pause_mix = advancePlaybackIcon(state.play_pause_mix, state.global_rate > 0, dt); result.draw = true
    }
    var hover = [state.hover_amount.0, state.hover_amount.1, state.hover_amount.2]
    for index in 0..<3 {
        let target: Double = state.global_hover_target == Int32(index + 5) ? 1 : 0
        if abs(hover[index] - target) > 0.001 {
            visual = visual || state.setting_animations
            hover[index] += (target - hover[index]) * (state.setting_animations ? 1 - exp(-dt * 10) : 1); result.draw = true
        }
    }
    state.hover_amount = (hover[0], hover[1], hover[2])
    if state.global_rate > 0 && state.global_anim_art_t < 1 {
        visual = true; state.global_anim_art_t = min(1, state.global_anim_art_t + dt / 0.3); result.draw = true
    } else if state.global_rate == 0 && state.global_anim_art_t > 0 {
        ambient = true; state.global_anim_art_t = max(0, state.global_anim_art_t - dt / 0.3); result.draw = true
    }
    result.interval = high ? 1 / 60 : visual ? 1 / 30 : ambient ? 1 / 20 : idleInterval > 0 && !compositorActive ? idleInterval : playback
    return result
}

func finishModeState(_ state: inout WallifyWidgetState) {
    state.mode_mix = 1; state.mode_transition_active = false; state.mode_from = state.setting_mode
    state.mode_start_width = state.mode_target_width; state.mode_start_height = state.mode_target_height
}

private let menuSelectionLock = NSLock()
private var menuSelection: Int32 = 0

@_cdecl("wallify_native_menu_selected")
public func enqueueContextSelection(_ tag: Int32) {
    menuSelectionLock.lock(); menuSelection = tag; menuSelectionLock.unlock()
    requestWidgetFrame()
}

@_cdecl("wallify_native_menu_action")
public func takeContextSelection() -> Int32 {
    menuSelectionLock.lock(); defer { menuSelectionLock.unlock() }
    let tag = menuSelection; menuSelection = 0; return tag
}

func applyContextSelection(_ tag: Int32) {
    let state = widgetStatePointer()
    switch tag {
    case 1: toggleWidgetPlayback()
    case 2: enqueueMediaCommand(5)
    case 3: enqueueMediaCommand(4)
    case 4: if state.pointee.setting_source == 2 { openSpotifast() } else { openSpotify() }
    case 5: applyWidgetBool(0, !state.pointee.setting_glow)
    case 6: applyWidgetBool(1, !state.pointee.setting_aurora)
    case 7: applyWidgetBool(2, !state.pointee.setting_animations)
    case 8: applyWidgetBool(3, !state.pointee.setting_dim)
    case 10...12: applyWidgetInt(10, tag - 10)
    case 20...22: applyWidgetInt(11, tag - 20)
    case 30...32: applyWidgetInt(12, tag - 30)
    case 40: restoreWidgetDefaults()
    case 50...52: applyWidgetInt(13, tag - 50)
    case 60...64: applyWidgetInt(14, tag - 60)
    case 70...75: applyWidgetInt(16, tag - 70)
    case 80...83: applyWidgetInt(15, tag == 80 ? 2 : tag == 81 ? 0 : tag == 82 ? 1 : 3)
    case 90: showSettingsWindow()
    default: break
    }
}

@_cdecl("wallify_swift_animation_loop")
public func runAnimationWorker() {
    var previousWidth = metalWidgetWidth(), previousTime = monotonicTime(), lastDraw = previousTime
    var marqueeTitle = "", marqueeWidth: Double = 0
    var rested = false
    while true {
        let now = monotonicTime()
        if !stateFlag(3, 0, false) {
            previousTime = now; lastDraw = now; _ = stateFlag(2, 1, false)
            waitForFrame(); rested = true; continue
        }
        sceneLock.lock()
        let state = widgetStatePointer(), width = metalWidgetWidth(), action = takeContextSelection()
        var dirty = stateFlag(2, 1, false) || width != previousWidth || action != 0
        previousWidth = width
        if action != 0 { applyContextSelection(action) }
        let title = widgetTitle()
        if !state.pointee.setting_hide_text && sceneLayout.geometry.compact_mix > 0.01 && title != marqueeTitle {
            marqueeTitle = title; marqueeWidth = textCache.width(title, 15, true)
        }
        let idle = spotifyIsIdle()
        // Waking from an indefinite wait is not a giant animation frame. Start
        // newly requested UI motion with dt=0, then let scheduled frames advance
        // it. Core Animation pets kept moving while this worker slept, however;
        // pass their real elapsed time separately so returning to Metal does not
        // jump back to the pose from before sleep. These two clocks intentionally
        // disagree on the first frame after rest.
        let step = advanceAnimations(&state.pointee, now: now, previous: rested ? now : previousTime, lastDraw: lastDraw, idle: idle,
            compositorActive: idleCompositor.active, compositorElapsed: idleCompositor.elapsed(now - previousTime), layout: sceneLayout, titleWidth: marqueeWidth,
            waveformAvailable: state.pointee.setting_waveform && state.pointee.global_rate > 0 && audioWaveform.textureAvailable())
        previousTime = now; rested = false
        if let (w, h) = step.resize { resizeMetalWidget(w, h) }
        if step.move { moveWidgetPanel(state.pointee.widget_margin_left, state.pointee.widget_margin_top); settingsPositionChanged() }
        if step.save { saveConfiguration() }
        dirty = dirty || step.draw
        if dirty { drawSwiftUIFrame(); lastDraw = monotonicTime() }
        sceneLock.unlock()
        let remaining = step.interval - (monotonicTime() - now)
        if step.interval == 0 { waitForFrame(); rested = true }
        else if remaining > 0 { waitForFrameInterval(UInt64(remaining * 1_000_000_000)) }
    }
}
