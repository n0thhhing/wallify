import Foundation

let primaryTextColor = SIMD4<Float>(245 / 255, 245 / 255, 247 / 255, 1)

func drawPlayerStatic(_ canvas: Canvas, card: WallifyCardRect, layout: SceneLayout, state: WallifyWidgetState, hasArtwork: Bool) {
    let g = layout.geometry, ease = smoothTransition(state.global_anim_art_t), inset = 10 * (1 - ease)
    let radiusDelta: Double = state.setting_artwork_radius == 0 ? -8 : state.setting_artwork_radius == 2 ? 8 : 0
    let art = cardRect(g.art_x + inset, g.art_y + inset, max(1, g.art_size - 2 * inset), max(1, g.art_size - 2 * inset), max(0, g.art_radius + radiusDelta - inset * g.compact_mix))
    let transition = min(1, max(0, 1 - (state.art_transition_until - state.animation_time) / 0.5))
    let mix = smoothTransition(transition)
    if state.setting_glow && state.global_has_artwork && hasArtwork {
        let size = Double(metalGlowExtent(132)) * g.art_size / 132
        let glow = cardRect(g.art_x + (g.art_size - size) / 2, g.art_y + (g.art_size - size) / 2, size, size)
        let intensity = state.setting_intensity == 0 ? 0.5 : state.setting_intensity == 2 ? 1.5 : 1
        var alpha = Float(0.5 * ease * intensity * (state.setting_native_glass ? 0.45 : 0.5))
        if state.setting_transition != 0 && mix < 1 { alpha *= 1 + 0.35 * Float(sin(mix * .pi)) }
        if mix < 1 { canvas.add(Int32(WALLIFY_GLOW), Texture.previousGlow.rawValue, glow, SIMD4(1, 1, 1, alpha * Float(1 - mix))) }
        canvas.add(Int32(WALLIFY_GLOW), Texture.glow.rawValue, glow, SIMD4(1, 1, 1, alpha * Float(mix)))
    }
    if state.global_has_artwork && hasArtwork {
        let dim: Float = state.setting_dim ? Float(0.6 + 0.4 * ease) : 1
        if state.setting_transition != 0 && mix < 1 {
            canvas.transition(state.setting_transition, art, Float(mix), Float(state.animation_time), SIMD3(Float(state.extracted_r) / 255, Float(state.extracted_g) / 255, Float(state.extracted_b) / 255), brightness: dim)
        } else {
            if mix < 1 { canvas.imageTint(.previousArtwork, art, SIMD4(dim, dim, dim, 1)) }
            canvas.imageTint(.artwork, art, SIMD4(dim, dim, dim, Float(mix)))
        }
        if g.compact_mix < 0.5 && state.setting_artwork_border { canvas.stroke(art, 0.5, SIMD4(1, 1, 1, 0.11)) }
    } else { canvas.fill(art, SIMD4(0.157, 0.157, 0.176, 1)) }
    if g.compact_mix > 0.5 && state.setting_compact_gradient {
        canvas.add(Int32(WALLIFY_GRADIENT), 0, cardRect(card.x, card.y + 84, card.w, max(0, card.h - 84)), SIMD4(0, 0, 0, 162 / 255))
    }
    if layout.controlsVisible(state.setting_show_controls) {
        for (index, button) in layout.buttons.enumerated() {
            let texture: Texture = index == 0 ? .previous : index == 2 ? .next : state.play_pause_mix < 0.5 ? .play : .pause
            let size = 48 * (index == 1 ? playbackIconScale(state.play_pause_mix, state.global_rate > 0) : 1)
            canvas.image(texture, cardRect(button.x - size / 2, button.y - size / 2, size, size))
        }
    }
}

func drawPlayerDynamic(_ canvas: Canvas, elapsed: Double, layout: SceneLayout, state: WallifyWidgetState) {
    drawPlayerProgress(canvas, elapsed: elapsed, layout: layout, state: state)
    if layout.controlsVisible(state.setting_show_controls) {
        let hover = [state.hover_amount.0, state.hover_amount.1, state.hover_amount.2]
        for index in 0..<3 where hover[index] > 0.001 { canvas.fill(layout.buttonBounds(index), SIMD4(1, 1, 1, Float(hover[index] * 31 / 255))) }
    }
    drawPlayerLabels(canvas, elapsed: elapsed, layout: layout, state: state)
}

func drawPlayerProgress(_ canvas: Canvas, elapsed: Double, layout: SceneLayout, state: WallifyWidgetState) {
    let g = layout.geometry
    if layout.progressVisible(state.setting_hide_progress) {
        let base: Double = state.setting_progress_thickness == 0 ? 3 : state.setting_progress_thickness == 2 ? 8 : 5
        let mix = smoothTransition(state.waveform_mix)
        let height = base + (max(12, base) - base) * mix + 4 * state.seek_expansion
        let bar = cardRect(g.bar_x, g.bar_y - (height - g.bar_h) / 2, g.bar_w, height, height / 2)
        let trackHeight = base + 4 * state.seek_expansion
        canvas.fill(cardRect(bar.x, bar.y + (height - trackHeight) / 2, bar.w, trackHeight, trackHeight / 2), SIMD4(0.176, 0.176, 0.176, 1))
        if state.global_duration > 0 {
            var progress = bar; progress.w *= min(1, max(0, elapsed / state.global_duration))
            if progress.w > 0 {
                if mix < 1 {
                    let normal = cardRect(progress.x, bar.y + (height - trackHeight) / 2, progress.w, trackHeight, trackHeight / 2)
                    canvas.fill(normal, SIMD4(1, 1, 1, Float(1 - mix)))
                }
                if mix > 0 {
                    progress.radius = 1
                    canvas.add(Int32(WALLIFY_WAVEFORM), Texture.waveform.rawValue, progress, SIMD4(1, 1, 1, Float(mix)))
                }
            }
        }
    }
}

func trackArtist(_ state: WallifyWidgetState) -> String {
    withUnsafeBytes(of: state.global_artist) { String(decoding: $0.prefix(state.global_artist_len), as: UTF8.self) }
}

func drawPlayerLabels(_ canvas: Canvas, elapsed: Double, layout: SceneLayout, state: WallifyWidgetState) {
    guard !state.setting_hide_text else { return }
    let g = layout.geometry, compact = min(1, max(0, g.compact_mix)), expanded = 1 - compact
    let scale = state.setting_font_scale == 0 ? 0.85 : state.setting_font_scale == 2 ? 1.15 : 1
    let title = state.global_title_len > 0 ? withUnsafeBytes(of: state.global_title) { String(decoding: $0.prefix(state.global_title_len), as: UTF8.self) } : "Not Playing"
    let artist = trackArtist(state), secondary = SIMD4<Float>(Float(max(145, state.extracted_r)) / 255, Float(max(145, state.extracted_g)) / 255, Float(max(145, state.extracted_b)) / 255, 1)
    if state.setting_clickable_names && (8...9).contains(state.global_hover_target) {
        let rect = layout.labelBounds(state.global_hover_target == 9, state: state)
        canvas.fill(cardRect(rect.x, rect.y + rect.h - 1, rect.w, 1), state.global_hover_target == 9 ? secondary : primaryTextColor)
    }
    if compact > 0.84 {
        textCache.draw(canvas, title, g.text_x, g.title_y, g.text_width, 15 * scale, 1, true, primaryTextColor, state.marquee_offset, false, false)
        textCache.draw(canvas, artist, g.text_x, g.artist_y, g.text_width, 11 * scale, 1, false, secondary)
        return
    }
    textCache.draw(canvas, title, g.text_x, g.title_y, g.text_width, 17 * scale, (15 + 2 * expanded) / 17, true, primaryTextColor)
    textCache.draw(canvas, artist.isEmpty ? "Play something to get started" : artist, g.text_x, g.artist_y, g.text_width, 14 * scale, (11 + 3 * expanded) / 14, false, secondary)
    guard expanded >= 0.88, state.setting_show_timestamps else { return }
    textCache.draw(canvas, formatTimestamp(elapsed), g.text_x, g.timestamp_y, 100, 12 * scale, 1, false, secondary, 0, false, false)
    textCache.draw(canvas, formatTimestamp(state.global_duration), g.text_x, g.timestamp_y, g.text_width, 12 * scale, 1, false, secondary, 0, true, false)
}

func formatTimestamp(_ seconds: Double) -> String {
    let value = seconds.isFinite ? Int(min(Double(Int32.max), max(0, seconds))) : 0
    let remainder = value % 60
    return "\(value / 60):" + (remainder < 10 ? "0" : "") + String(remainder)
}

func drawIdleScene(_ canvas: Canvas, card: WallifyCardRect, layout: SceneLayout, state: WallifyWidgetState) {
    canvas.opacity = Float(smoothTransition(state.idle_mix))
    if !state.setting_native_glass { canvas.fill(card, SIMD4(30 / 255, 29 / 255, 32 / 255, 1)) }
    if state.setting_idle_style != 0 {
        canvas.pet(Int32(state.setting_idle_style - 1), card, state.cat_time, state.animation_time < state.cat_pet_until)
    } else {
        let g = layout.geometry, compact = g.compact_mix > 0.5, size = compact ? card.w : g.art_size
        let padded = size * 128 / 104, inset = (padded - size) / 2
        canvas.image(.spotify, cardRect(g.art_x - inset, g.art_y - inset, padded, padded))
        if !compact {
            textCache.draw(canvas, "Open Spotify", g.text_x, g.title_y, g.text_width, 17, 1, true, primaryTextColor)
            textCache.draw(canvas, "Click to launch", g.text_x, g.artist_y, g.text_width, 13, 1, false, SIMD4(0.62, 0.60, 0.57, 1))
        }
    }
}
