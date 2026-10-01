import Foundation

func checkWaveform() {
    let samples: [Float] = (0..<128).map { $0 % 2 == 0 ? -0.5 : 0.25 }
    assert(samples.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff0072e5 })
    let invalid: [Float] = [.nan, .infinity]
    assert(invalid.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff000000 })
    let clipped: [Float] = (0..<128).map { $0 % 2 == 0 ? -2 : 2 }
    assert(clipped.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff00e5e5 })
    let quiet: [Float] = (0..<128).map { $0 % 2 == 0 ? -0.05 : 0.05 }
    assert(quiet.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff009999 })
    var state = WallifyWidgetState(); state.global_duration = 100; state.setting_waveform = true
    var layout = SceneLayout(); layout.update(width: 540, height: 180, state: state)
    for elapsed in [0.0, 50, 150] {
        let canvas = Canvas(clip: layout.card)
        drawPlayerProgress(canvas, elapsed: elapsed, layout: layout, state: state, waveform: true)
        let waves = canvas.commands.filter { $0.kind == Int32(WALLIFY_WAVEFORM) }
        assert(waves.count == (elapsed > 0 ? 1 : 0))
        if let wave = waves.first {
            assert(canvas.commands.first!.dh == 3)
            assert(abs(Double(wave.dw) - layout.geometry.bar_w * min(1, elapsed / 100)) < 0.001)
            assert(wave.dh == 12)
        }
    }
    let fallback = Canvas(clip: layout.card)
    drawPlayerProgress(fallback, elapsed: 50, layout: layout, state: state, waveform: false)
    assert(fallback.commands.count == 2 && fallback.commands.allSatisfy { $0.kind != Int32(WALLIFY_WAVEFORM) })
}
