import Foundation

func checkLayoutInterpolation() {
    func fields(_ layout: WallifyLayoutGeometry) -> [Double] {
        withUnsafeBytes(of: layout) { Array($0.bindMemory(to: Double.self)) }
    }
    for from in Int32(0)..<5 {
        for to in Int32(0)..<5 {
            var a = WallifyLayoutGeometry(), b = WallifyLayoutGeometry(), result = WallifyLayoutGeometry()
            precondition(widgetLayoutGeometry(from, from, 0, &a) && widgetLayoutGeometry(to, to, 1, &b))
            let start = fields(a), end = fields(b)
            precondition(start.count == 16)
            for mix in [-1.0, 0, 0.13, 0.5, 0.87, 1, 2] {
                precondition(widgetLayoutGeometry(from, to, mix, &result))
                let t = min(1, max(0, mix)), actual = fields(result)
                for i in 0..<16 { precondition(abs(actual[i] - (start[i] + (end[i] - start[i]) * t)) < 1e-10) }
            }
        }
    }
    var layout = WallifyLayoutGeometry()
    precondition(!widgetLayoutGeometry(-1, 0, 0, &layout) && !widgetLayoutGeometry(0, 5, 0, &layout))
    precondition(!widgetLayoutGeometry(0, 1, .nan, &layout) && !widgetLayoutGeometry(0, 1, 0, nil))
}

func checkPerformanceSample() {
    var sample = PerformanceSample()
    sample.update(now: 10, cpu: 2, frames: 100, gpu: 1_000_000)
    precondition(sample.cpuPercent == 0)
    sample.update(now: 12, cpu: 2.5, frames: 140, gpu: 81_000_000)
    precondition(sample.cpuPercent == 25 && sample.redraws == 20 && sample.gpuMS == 2)
    sample.update(now: 14, cpu: 2.5, frames: 140, gpu: 81_000_000)
    precondition(sample.cpuPercent == 0 && sample.redraws == 0 && sample.gpuMS == 0)
    sample.update(now: 15, cpu: 1, frames: 0, gpu: 0)
    precondition(sample.cpuPercent == 0 && sample.redraws == 0 && sample.gpuMS == 0)
}

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

func benchmarkMath() {
    let pixels = (0..<180 * 180).map { UInt32(truncatingIfNeeded: $0 &* 2654435761) }
    var layout = WallifyLayoutGeometry(), checksum = 0.0
    var layoutSamples = [Double](), colorSamples = [Double]()
    for _ in 0..<5 {
        var started = monotonicTime()
        for i in 0..<20_000 {
            precondition(widgetLayoutGeometry(Int32(i % 5), Int32((i + 1) % 5), Double(i % 101) / 100, &layout))
            checksum += withUnsafeBytes(of: layout) { $0.bindMemory(to: Double.self).reduce(0, +) }
        }
        layoutSamples.append((monotonicTime() - started) * 1_000_000 / 20_000)
        started = monotonicTime()
        for _ in 0..<500 {
            let color = artworkColor(pixels)
            checksum += Double(color.0) + Double(color.1) + Double(color.2)
        }
        colorSamples.append((monotonicTime() - started) * 1_000_000 / 500)
    }
    print(String(format: "layout_us=%.3f artwork_color_us=%.3f checksum=%.0f", layoutSamples.sorted()[2], colorSamples.sorted()[2], checksum))
}

func benchmarkSnap() {
    let candidates: [WallifyWindowRect] = (0..<64).map { index in
        let x = Double(index % 8) * 220, y = Double(index / 8) * 200
        let width: Double = index % 2 == 0 ? 180 : 360
        return WallifyWindowRect(x: x, y: y, width: width, height: 180)
    }
    var samples = [Double](), checksum = 0.0
    candidates.withUnsafeBufferPointer { buffer in
        for _ in 0..<5 {
            let start = monotonicTime()
            for i in 0..<2000 {
                var snap = WallifyPanelSnap()
                calculatePanelSnap(buffer.baseAddress, UInt(buffer.count), Double(i % 1000), Double(i % 700),
                                   540, 180, 0, 0, 0, 0, &snap)
                checksum += snap.distance_sq + Double(snap.margin_left) + Double(snap.margin_top)
            }
            samples.append((monotonicTime() - start) * 1_000_000 / 2000)
        }
    }
    print(String(format: "snap_us=%.3f checksum=%.0f", samples.sorted()[2], checksum))
}
