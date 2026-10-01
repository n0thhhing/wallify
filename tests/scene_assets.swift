import Foundation

func checkSceneAssets() {
    let textScratch = TextCache()
    precondition(textScratch.width("Short", 17, false) > 0)
    precondition(textScratch.scratchBytes > 0 && textScratch.scratchBytes < 2048 * 96 * 4)
    let black = artworkColor([0xff000000])
    precondition(black.0 == 0 && black.1 == 0 && black.2 == 0)
    let color = artworkColor([0xff201008, 0xff201008])
    precondition(color.0 == 40 && color.1 == 80 && color.2 == 160)
    for (name, count) in [("cat_pixels.bin", 541 * 52), ("banana_pixels.bin", 98 * 114 * 45), ("raccoon_pixels.bin", 550 * 68)] {
        let url = assetURL(name)!
        let bytes = Array(try! Data(contentsOf: url))
        var pixels = [UInt32](repeating: 0, count: count)
        precondition(bytes.withUnsafeBufferPointer { input in pixels.withUnsafeMutableBufferPointer {
            decodeSpriteRLE(input.baseAddress, UInt(input.count), $0.baseAddress, UInt($0.count))
        } })
    }
    let canvas = Canvas(clip: cardRect(8, 8, 164, 164, 26))
    canvas.opacity = 0.5
    canvas.fill(cardRect(1, 2, 10, 12, 3), SIMD4(1, 0, 0, 0.6))
    precondition(abs(canvas.commands[0].alpha - 0.3) < 0.0001 && canvas.commands[0].clip_radius == 26)
    canvas.glass(canvas.clip, SIMD4(0.1, 0.1, 0.1, 1), SIMD3(0.8, 0.4, 0.2), 0.15)
    precondition(canvas.commands[1].kind == WALLIFY_GLASS && canvas.commands[1].sx == 0.8)
    for style in UInt8(1)...5 {
        canvas.transition(style, canvas.clip, 0.5, 4, SIMD3(0.8, 0.4, 0.2))
        precondition(canvas.commands.last!.kind == WALLIFY_CINEMATIC + Int32(style) - 1)
    }
    try! sceneAssets.initialize()
    for style in UInt8(1)...3 { try! sceneAssets.ensurePet(style) }
    let catTexture = metalRenderer.texture(Texture.cat.rawValue)!
    try! sceneAssets.ensurePet(1)
    precondition(metalRenderer.texture(Texture.cat.rawValue)! === catTexture)
    precondition(metalRenderer.texture(Texture.cat.rawValue)!.width == 541)
    precondition(metalRenderer.texture(Texture.banana.rawValue)!.height == 114 * 45)
    precondition(formatTimestamp(125.8) == "2:05" && formatTimestamp(.infinity) == "0:00")
    for seconds in 0..<3600 {
        precondition(formatTimestamp(Double(seconds)) == "\(seconds / 60):" + String(format: "%02d", seconds % 60))
    }
    precondition(formatTimestamp(-1) == "0:00" && formatTimestamp(.nan) == "0:00")
    var state = widgetStatePointer().pointee
    state.setting_show_controls = true; state.setting_hide_progress = false; state.setting_hide_text = false
    state.global_duration = 200; state.global_anim_art_t = 1; state.global_rate = 1
    state.setting_dim = true; state.setting_transition = 0; state.global_has_artwork = true
    let artworkLayout = SceneLayout()
    func artworkBrightness() -> Float {
        let scene = Canvas(clip: artworkLayout.card)
        drawPlayerStatic(scene, card: artworkLayout.card, layout: artworkLayout, state: state, hasArtwork: true)
        return scene.commands.first { $0.texture_id == Texture.artwork.rawValue }!.r
    }
    precondition(artworkBrightness() == 1)
    let playingKey = StaticSceneKey(layout: artworkLayout, state: state, hasArtwork: true, generation: 1)
    state.global_rate = 0
    precondition(artworkBrightness() == 1) // Pausing must start from the current brightness.
    state.global_anim_art_t = 0.5
    precondition(artworkBrightness() > 0.6 && artworkBrightness() < 1)
    state.global_anim_art_t = 0
    precondition(artworkBrightness() == 0.6)
    state.art_transition_until = state.animation_time + 0.25
    for style in UInt8(1)...5 {
        state.setting_transition = style
        let scene = Canvas(clip: artworkLayout.card)
        drawPlayerStatic(scene, card: artworkLayout.card, layout: artworkLayout, state: state, hasArtwork: true)
        precondition(scene.commands.first { $0.kind == WALLIFY_CINEMATIC + Int32(style) - 1 }!.sh == 0.6)
    }
    state.art_transition_until = 0; state.setting_transition = 0
    precondition(playingKey != StaticSceneKey(layout: artworkLayout, state: state, hasArtwork: true, generation: 1))
    state.global_rate = 1; state.global_anim_art_t = 1
    for mode in UInt8(0)...4 {
        let (w, h) = modeDimensions(mode)
        state.setting_mode = mode; state.mode_from = mode; state.mode_mix = 1
        var layout = SceneLayout(); layout.update(width: w, height: h, state: state)
        precondition(layout.card.w == w - 16 && layout.card.h == h - 16)
        let staticCanvas = Canvas(clip: layout.card), dynamic = Canvas(clip: layout.card)
        drawPlayerStatic(staticCanvas, card: layout.card, layout: layout, state: state, hasArtwork: false)
        drawPlayerDynamic(dynamic, elapsed: 100, layout: layout, state: state)
        precondition(staticCanvas.commands.count + dynamic.commands.count < WALLIFY_MAX_COMMANDS)
        let controls = staticCanvas.commands.filter { (10...11).contains($0.texture_id) || $0.texture_id == 8 || $0.texture_id == 9 }
        precondition(controls.count == (mode == 0 ? 0 : 3))
        if mode != 0 {
            let progress = dynamic.commands.filter { $0.kind == WALLIFY_SOLID && $0.alpha == 1 }
            precondition(progress.count == 2 && abs(progress[1].dw * 2 - progress[0].dw) < 0.001)
        }
    }
    for i in 0..<40 {
        let text = Canvas(clip: cardRect(0, 0, 180, 180))
        textCache.draw(text, "café \(i)", 0, 0, 20, 17, 1, true, SIMD4(1, 1, 1, 1))
        precondition(!text.commands.isEmpty && text.commands.allSatisfy { (13...28).contains($0.texture_id) })
    }
}
