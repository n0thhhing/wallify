import Foundation

// Renderer/animation caches are owned by one worker. Native state access uses this
// recursive lock so callbacks can request/save while the worker updates a frame.
// ponytail: one scene lock; split state from caches only if measured contention warrants it.
let sceneLock = NSRecursiveLock()

// This is the CPU half of the static-scene cache. The Metal half compares draw
// command bytes, which cannot see that an artwork texture changed in place of
// the previous slot contents. Include the asset generation here so new artwork
// forces command preparation too. During a crossfade, animation_time belongs in
// the key because yesterday's "static" artwork is moving; after the transition
// it becomes zero again so normal progress ticks reuse the same static scene.
// When adding a setting, include it here if drawPlayerStatic or the card/frame
// drawing reads it, otherwise the effect may appear only after another change.
struct StaticSceneKey: Equatable {
    let geometry: [Double]
    let settings: [UInt8]
    let flags: [Bool]
    let generation: UInt64
    init(layout: SceneLayout, state: WallifyWidgetState, hasArtwork: Bool, generation: UInt64) {
        geometry = [layout.width, layout.height, state.mode_mix, state.idle_mix, state.global_anim_art_t, state.play_pause_mix,
                    state.art_transition_until > state.animation_time ? state.animation_time : 0]
        settings = [state.mode_from, state.setting_mode, state.setting_artwork_radius, state.setting_frame,
                    state.setting_intensity, state.setting_transition, state.extracted_r, state.extracted_g, state.extracted_b]
        flags = [state.setting_native_glass, state.setting_glow, state.setting_dim, state.setting_compact_gradient,
                 state.setting_show_controls, state.setting_artwork_border, state.global_has_artwork, hasArtwork,
                 state.art_transition_until > state.animation_time, state.global_rate > 0]
        self.generation = generation
    }
}

private var cachedSceneKey: StaticSceneKey?
private var cachedScene = Canvas(clip: WallifyCardRect())

@_cdecl("wallify_scene_artwork_dirty")
public func markSceneArtworkDirty() { sceneAssets.markArtworkDirty() }
@_cdecl("wallify_scene_clear_artwork")
public func clearSceneArtwork() { sceneAssets.clearArtwork() }

@_cdecl("wallify_swift_draw_frame")
public func drawSwiftUIFrame() {
    let started = monotonicTime()
    sceneLock.lock()
    defer { sceneLock.unlock(); profileMetalScene(monotonicTime() - started) }
    do { try sceneAssets.initialize() }
    catch { NSLog("Wallify: scene assets failed: %@", error.localizedDescription); return }
    sceneAssets.refreshArtwork()
    var state = widgetStatePointer().pointee
    if terminalMode { state.setting_native_glass = false }
    if state.idle_mix > 0 {
        do { try sceneAssets.ensurePet(state.setting_idle_style) }
        catch { NSLog("Wallify: pet sprite failed: %@", error.localizedDescription); return }
    }
    sceneLayout.update(width: Double(metalWidgetWidth()), height: Double(metalWidgetHeight()), state: state)
    let layout = sceneLayout, card = layout.card
    if stoppedWidgetHidden(state) {
        stopIdleAnimation()
        if terminalMode { presentMetalScene(Float(layout.width), Float(layout.height), nil, 0, nil, 0) }
        return
    }
    if state.setting_waveform {
        audioWaveform.update(active: state.global_rate > 0 && state.global_duration > 0 && state.setting_animations &&
            state.idle_mix < 1 && layout.progressVisible(state.setting_hide_progress) && stateFlag(3, 0, false))
    }
    idleCompositor.update(card: card, state: state)
    let clip = state.setting_native_glass ? WallifyCardRect() : card
    let color = SIMD3<Float>(Float(state.extracted_r) / 255, Float(state.extracted_g) / 255, Float(state.extracted_b) / 255)
    updateDesktopGlass(card.x, card.y, card.w, card.h, card.radius, color.x, color.y, color.z, state.setting_native_glass)
    let key = StaticSceneKey(layout: layout, state: state, hasArtwork: sceneAssets.hasArtwork, generation: sceneAssets.generation)
    if cachedSceneKey != key {
        cachedScene = Canvas(clip: clip)
        if !state.setting_native_glass {
            cachedScene.glass(card, SIMD4(28 / 255, 28 / 255, 30 / 255, 1), color,
                state.global_has_artwork && sceneAssets.hasArtwork && state.setting_glow ? 0.12 : 0)
        }
        if state.idle_mix < 1 {
            cachedScene.opacity = Float(1 - smoothTransition(state.idle_mix))
            drawPlayerStatic(cachedScene, card: card, layout: layout, state: state, hasArtwork: sceneAssets.hasArtwork)
            cachedScene.opacity = 1
        }
        let frame = state.setting_frame == 0 ? 0 : state.setting_frame == 2 ? 1.5 : 1
        if !state.setting_native_glass && frame > 0 { cachedScene.stroke(card, 0.8, SIMD4(1, 1, 1, Float(0.12 * frame))) }
        cachedSceneKey = key
    }
    let dynamic = Canvas(clip: clip)
    dynamic.image(.cachedScene, cardRect(0, 0, layout.width, layout.height))
    if !state.setting_native_glass && state.aurora_mix > 0.001 && state.global_has_artwork && sceneAssets.hasArtwork {
        let dim = state.setting_dim && state.global_rate == 0 ? 0.65 : 1
        dynamic.aurora(card, color, Float(state.animation_time), Float(0.32 * state.aurora_mix * (1 - state.idle_mix) * dim))
    }
    if state.idle_mix < 1 {
        let elapsed = state.global_rate == 0 || state.global_is_dragging ? state.global_elapsed : playbackPosition(state.playback_clock, now: monotonicTime(), duration: state.global_duration)
        dynamic.opacity = Float(1 - smoothTransition(state.idle_mix))
        drawPlayerDynamic(dynamic, elapsed: elapsed, layout: layout, state: state)
    }
    if state.idle_mix > 0 && !idleCompositor.active { drawIdleScene(dynamic, card: card, layout: layout, state: state) }
    cachedScene.commands.withUnsafeBufferPointer { statics in dynamic.commands.withUnsafeBufferPointer {
        presentMetalScene(Float(layout.width), Float(layout.height), statics.baseAddress, UInt(statics.count), $0.baseAddress, UInt($0.count))
    } }
}
