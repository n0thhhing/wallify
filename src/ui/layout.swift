import Foundation

// Nominal layouts use the same 180-point desktop grid as the window modes.
// Window resizing interpolates between these endpoints, including input targets.
private let widgetLayouts: [WallifyLayoutGeometry] = [
    WallifyLayoutGeometry(art_x: 8, art_y: 8, art_size: 164, art_radius: 26,
        bar_x: 16, bar_y: 112, bar_w: 132, bar_h: 5, text_x: 16, text_width: 132,
        title_y: 116, artist_y: 137, timestamp_y: 99, button_center: 90, button_y: 48, compact_mix: 1),
    WallifyLayoutGeometry(art_x: 24, art_y: 24, art_size: 132, art_radius: 14,
        bar_x: 172, bar_y: 84, bar_w: 164, bar_h: 5, text_x: 172, text_width: 164,
        title_y: 30, artist_y: 54, timestamp_y: 99, button_center: 254, button_y: 132, compact_mix: 0),
    WallifyLayoutGeometry(art_x: 24, art_y: 24, art_size: 132, art_radius: 14,
        bar_x: 172, bar_y: 84, bar_w: 344, bar_h: 5, text_x: 172, text_width: 344,
        title_y: 30, artist_y: 54, timestamp_y: 99, button_center: 344, button_y: 132, compact_mix: 0),
    WallifyLayoutGeometry(art_x: 16, art_y: 20, art_size: 148, art_radius: 18,
        bar_x: 16, bar_y: 252, bar_w: 148, bar_h: 5, text_x: 16, text_width: 148,
        title_y: 188, artist_y: 214, timestamp_y: 264, button_center: 90, button_y: 312, compact_mix: 0),
    WallifyLayoutGeometry(art_x: 84, art_y: 24, art_size: 192, art_radius: 26,
        bar_x: 24, bar_y: 280, bar_w: 312, bar_h: 5, text_x: 24, text_width: 312,
        title_y: 228, artist_y: 254, timestamp_y: 292, button_center: 180, button_y: 326, compact_mix: 0)
]

// Pack the fixed endpoints once; resizing interpolates all 16 fields without key-path dispatch.
private let layoutVectors = widgetLayouts.map {
    SIMD16<Double>($0.art_x, $0.art_y, $0.art_size, $0.art_radius,
                   $0.bar_x, $0.bar_y, $0.bar_w, $0.bar_h,
                   $0.text_x, $0.text_width, $0.title_y, $0.artist_y,
                   $0.timestamp_y, $0.button_center, $0.button_y, $0.compact_mix)
}

@_cdecl("wallify_layout_geometry")
public func widgetLayoutGeometry(_ fromMode: Int32, _ toMode: Int32, _ mix: Double,
                                  _ output: UnsafeMutablePointer<WallifyLayoutGeometry>?) -> Bool {
    guard let output = output, (0..<5).contains(fromMode), (0..<5).contains(toMode), mix.isFinite else { return false }
    let from = layoutVectors[Int(fromMode)]
    let to = layoutVectors[Int(toMode)]
    let t = min(1, max(0, mix))
    let v = from + (to - from) * SIMD16(repeating: t)
    output.pointee = WallifyLayoutGeometry(art_x: v[0], art_y: v[1], art_size: v[2], art_radius: v[3],
        bar_x: v[4], bar_y: v[5], bar_w: v[6], bar_h: v[7], text_x: v[8], text_width: v[9],
        title_y: v[10], artist_y: v[11], timestamp_y: v[12], button_center: v[13], button_y: v[14], compact_mix: v[15])
    return true
}

@_cdecl("wallify_rounded_contains")
public func roundedContains(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                            _ radius: Double, _ px: Double, _ py: Double) -> Bool {
    guard [x, y, width, height, radius, px, py].allSatisfy({ $0.isFinite }), width > 0, height > 0,
          px >= x, py >= y, px < x + width, py < y + height else { return false }
    let r = max(0, min(radius, min(width, height) / 2))
    let dx = max(max(x + r - px, px - (x + width - r)), 0)
    let dy = max(max(y + r - py, py - (y + height - r)), 0)
    return dx * dx + dy * dy <= r * r
}

struct SceneLayout {
    var width: Double = 540, height: Double = 180
    var geometry = widgetLayouts[2]
    private var from: UInt8 = 2, to: UInt8 = 2
    private var mix: Double = 1

    mutating func update(width: Double, height: Double, state: WallifyWidgetState) {
        guard self.width != width || self.height != height || from != state.mode_from || to != state.setting_mode || mix != state.mode_mix else { return }
        self.width = width; self.height = height; from = state.mode_from; to = state.setting_mode; mix = state.mode_mix
        _ = widgetLayoutGeometry(Int32(from), Int32(to), smoothTransition(mix), &geometry)
    }
    var card: WallifyCardRect { cardRect(8, 8, max(0, width - 16), max(0, height - 16), 26) }
    var buttons: [(x: Double, y: Double)] { [-1.0, 0, 1].map { (geometry.button_center + $0 * 46, geometry.button_y) } }
    func buttonBounds(_ index: Int) -> WallifyCardRect {
        let radius: Double = index == 1 ? 20 : 15, button = buttons[index]
        return cardRect(button.x - radius, button.y - radius, radius * 2, radius * 2, radius)
    }
    func controlsVisible(_ enabled: Bool) -> Bool { enabled && geometry.compact_mix <= 0.5 }
    func progressVisible(_ hidden: Bool) -> Bool { !hidden && geometry.compact_mix <= 0.5 }
    func labelBounds(_ artist: Bool, state: WallifyWidgetState) -> WallifyCardRect {
        guard state.setting_clickable_names, !state.setting_hide_text,
              (artist ? state.global_artist_len : state.global_title_len) > 0 else { return WallifyCardRect() }
        let title = withUnsafeBytes(of: state.global_title) { String(decoding: $0.prefix(state.global_title_len), as: UTF8.self) }
        guard !placeholderTitle(title) else { return WallifyCardRect() }
        let scale = state.setting_font_scale == 0 ? 0.85 : state.setting_font_scale == 2 ? 1.15 : 1
        let compact = min(1, max(0, geometry.compact_mix))
        let font = compact > 0.84 ? (artist ? 11.0 : 15.0) : (artist ? 14 - 3 * compact : 17 - 2 * compact)
        // Match the rasterizer's 1.5-em line box, capped before the next row.
        // These bounds stay independent of the worker-owned GPU text cache.
        let height = min(font * scale * 1.5, artist ? .infinity : geometry.artist_y - geometry.title_y)
        let bytes = artist ? withUnsafeBytes(of: state.global_artist) { Array($0.prefix(state.global_artist_len)) } :
            withUnsafeBytes(of: state.global_title) { Array($0.prefix(state.global_title_len)) }
        let width = bytes.withUnsafeBufferPointer { ceil(rasterTextWidth($0.baseAddress, UInt($0.count), font * scale * 2, artist ? 0 : 1)) / 2 + 4 }
        return cardRect(geometry.text_x, artist ? geometry.artist_y : geometry.title_y, min(geometry.text_width, width), height)
    }
    func inputGeometry(_ state: WallifyWidgetState) -> WallifyInputGeometry {
        WallifyInputGeometry(card: card, art: cardRect(geometry.art_x, geometry.art_y, geometry.art_size, geometry.art_size, 14),
            bar: cardRect(geometry.bar_x, geometry.bar_y - 14, geometry.bar_w, geometry.bar_h + 28, 3),
            buttons: (buttonBounds(0), buttonBounds(1), buttonBounds(2)),
            title: labelBounds(false, state: state), artist: labelBounds(true, state: state), bar_x: geometry.bar_x, bar_width: geometry.bar_w,
            controls_visible: controlsVisible(state.setting_show_controls), progress_visible: progressVisible(state.setting_hide_progress))
    }
}

var sceneLayout = SceneLayout()
