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

@_cdecl("wallify_layout_geometry")
public func widgetLayoutGeometry(_ fromMode: Int32, _ toMode: Int32, _ mix: Double,
                                  _ output: UnsafeMutablePointer<WallifyLayoutGeometry>?) -> Bool {
    guard let output = output, (0..<5).contains(fromMode), (0..<5).contains(toMode), mix.isFinite else { return false }
    let from = widgetLayouts[Int(fromMode)]
    let to = widgetLayouts[Int(toMode)]
    let t = min(1, max(0, mix))
    let fields: [WritableKeyPath<WallifyLayoutGeometry, Double>] = [
        \.art_x, \.art_y, \.art_size, \.art_radius, \.bar_x, \.bar_y, \.bar_w, \.bar_h,
        \.text_x, \.text_width, \.title_y, \.artist_y, \.timestamp_y, \.button_center, \.button_y, \.compact_mix
    ]
    var result = from
    for field in fields { result[keyPath: field] = from[keyPath: field] + (to[keyPath: field] - from[keyPath: field]) * t }
    output.pointee = result
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
