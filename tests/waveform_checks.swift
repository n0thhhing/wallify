import Foundation
import Metal

func checkWaveform() {
    let samples: [Float] = (0..<128).map { $0 % 2 == 0 ? -0.5 : 0.25 }
    precondition(samples.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff0072e5 })
    let invalid: [Float] = [.nan, .infinity]
    precondition(invalid.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff000000 })
    let clipped: [Float] = (0..<128).map { $0 % 2 == 0 ? -2 : 2 }
    precondition(clipped.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff00e5e5 })
    let quiet: [Float] = (0..<128).map { $0 % 2 == 0 ? -0.05 : 0.05 }
    precondition(quiet.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { $0 == 0xff00e5e5 })
    let attenuated = samples.map { $0 * 0.01 }
    precondition(attenuated.withUnsafeBufferPointer { waveformPixels($0) }.allSatisfy { ($0 & 255) > 200 })
    var state = WallifyWidgetState(); state.global_duration = 100; state.setting_waveform = true
    state.setting_mode = 2; state.mode_from = 2; state.mode_mix = 1
    var layout = SceneLayout(); layout.update(width: 540, height: 180, state: state)
    for elapsed in [0.0, 50, 150] {
        let canvas = Canvas(clip: layout.card)
        drawPlayerProgress(canvas, elapsed: elapsed, layout: layout, state: state, waveform: true)
        let waves = canvas.commands.filter { $0.kind == Int32(WALLIFY_WAVEFORM) }
        precondition(waves.count == (elapsed > 0 ? 1 : 0))
        if let wave = waves.first {
            precondition(canvas.commands.first!.dh == 3)
            precondition(abs(Double(wave.dw) - layout.geometry.bar_w * min(1, elapsed / 100)) < 0.001)
            precondition(wave.dh == 12)
        }
    }
    let fallback = Canvas(clip: layout.card)
    drawPlayerProgress(fallback, elapsed: 50, layout: layout, state: state, waveform: false)
    precondition(fallback.commands.count == 2 && fallback.commands.allSatisfy { $0.kind != Int32(WALLIFY_WAVEFORM) })
    let renderer = metalRenderer
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 12, mipmapped: false)
    descriptor.storageMode = .shared; descriptor.usage = .renderTarget
    let target = renderer.device!.makeTexture(descriptor: descriptor)!
    func coverage(_ samples: [Float]) -> Int {
        let pixels = samples.withUnsafeBufferPointer { waveformPixels($0) }
        pixels.withUnsafeBufferPointer { renderer.loadTexture(Texture.waveform.rawValue, pixels: $0.baseAddress, width: 64, height: 1) }
        var textures = [MTLTexture?](repeating: renderer.texture(0), count: Int(WALLIFY_MAX_TEXTURES))
        textures[Int(Texture.waveform.rawValue)] = renderer.texture(Texture.waveform.rawValue)
        let canvas = Canvas(clip: cardRect(0, 0, 64, 12))
        canvas.add(Int32(WALLIFY_WAVEFORM), Texture.waveform.rawValue, cardRect(0, 0, 64, 12), SIMD4(1, 1, 1, 1))
        let command = renderer.queue!.makeCommandBuffer()!
        canvas.commands.withUnsafeBufferPointer {
            precondition(renderer.encode(command, target: target, commands: $0.baseAddress!, count: 1, size: SIMD2(64, 12), textures: textures))
        }
        command.commit(); command.waitUntilCompleted()
        precondition(command.status == .completed)
        var output = [UInt32](repeating: 0, count: 64 * 12)
        output.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: 256, from: MTLRegionMake2D(0, 0, 64, 12), mipmapLevel: 0) }
        return output.filter { ($0 >> 24) > 128 }.count
    }
    precondition(coverage(samples) > coverage([Float](repeating: 0, count: 128)) * 2, "Audio amplitude must change rendered bar height")
}
