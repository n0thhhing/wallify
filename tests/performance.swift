import Foundation

func benchmarkFramePreparation() {
    let state = widgetStatePointer()
    state.pointee.setting_source = 0; state.pointee.global_rate = 1
    state.pointee.global_duration = 600; state.pointee.global_has_artwork = false
    state.pointee.global_anim_art_t = 1; state.pointee.play_pause_mix = 1
    state.pointee.setting_aurora = false; state.pointee.aurora_mix = 0
    updateTrackText(Array("A steady playback benchmark".utf8), Array("Artist".utf8), state: state)
    resizeMetalWidget(540, 180)
    drawSwiftUIFrame()
    for i in 0..<100 { state.pointee.global_elapsed = Double(i) / 20; drawSwiftUIFrame() }
    var samples = [Double]()
    for _ in 0..<5 {
        let started = monotonicTime()
        for i in 0..<2000 { state.pointee.global_elapsed = Double(i) / 20; drawSwiftUIFrame() }
        samples.append((monotonicTime() - started) * 1_000_000 / 2000)
    }
    let stats = metalRenderer.stats()
    print(String(format: "frame_prepare_us=%.3f texture_bytes=%llu text_scratch_bytes=%d", samples.sorted()[2], stats.texture_bytes, textCache.scratchBytes))
}
