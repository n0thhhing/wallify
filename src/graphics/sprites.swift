import Foundation

@_cdecl("wallify_decode_sprite_rle")
public func decodeSpriteRLE(_ input: UnsafePointer<UInt8>?, _ length: UInt,
                            _ output: UnsafeMutablePointer<UInt32>?, _ pixelCount: UInt) -> Bool {
    if length == 0 && pixelCount == 0 { return true }
    guard let input = input, let output = output, length <= UInt(Int.max), pixelCount <= UInt(Int.max) else { return false }
    let bytes = UnsafeBufferPointer(start: input, count: Int(length))
    var source = 0
    var destination = 0
    while source < bytes.count && destination < Int(pixelCount) {
        let header = bytes[source]
        source += 1
        let count = Int(header & 127)
        let repeated = header & 128 != 0
        let byteCount = repeated ? 4 : count * 4
        guard count > 0, count <= Int(pixelCount) - destination, byteCount <= bytes.count - source else { return false }
        for index in 0..<count {
            let offset = source + (repeated ? 0 : index * 4)
            let alpha = UInt32(bytes[offset + 3])
            let red = (UInt32(bytes[offset]) * alpha + 127) / 255
            let green = (UInt32(bytes[offset + 1]) * alpha + 127) / 255
            let blue = (UInt32(bytes[offset + 2]) * alpha + 127) / 255
            output[destination] = red | (green << 8) | (blue << 16) | (alpha << 24)
            destination += 1
        }
        source += byteCount
    }
    return destination == Int(pixelCount) && source == bytes.count
}

let sleepStrips = [(0, 0, 5), (3, 1, 1), (2, 2, 1), (1, 3, 1), (0, 4, 5)]
let heartStrips = [(1, 0, 1), (3, 0, 1), (0, 1, 5), (0, 2, 5), (1, 3, 3), (2, 4, 1)]
private let catRegions: [(x: Double, width: Double, height: Double)] = [
    (0, 110, 52), (110, 108, 52), (218, 107, 50), (326, 107, 50), (434, 107, 51)
]

func petFrame(_ time: Double, fps: Double, frames: Int) -> Int {
    let value = time * fps
    guard value.isFinite else { return 0 }
    let remainder = value.truncatingRemainder(dividingBy: Double(frames))
    return Int(floor(remainder < 0 ? remainder + Double(frames) : remainder))
}

@_cdecl("wallify_raccoon_frame")
public func raccoonFrame(_ time: Double) -> UInt { UInt(petFrame(time, fps: 3, frames: 5)) }

@_cdecl("wallify_draw_pet")
public func drawPet(_ style: Int32, _ card: UnsafePointer<WallifyCardRect>?, _ clip: UnsafePointer<WallifyCardRect>?,
                    _ time: Double, _ petted: Bool, _ opacity: Float,
                    _ output: UnsafeMutablePointer<DrawCommand>?, _ capacity: UInt) -> UInt {
    guard let card = card?.pointee, let clip = clip?.pointee, let output = output,
          (0...3).contains(style), time.isFinite, opacity.isFinite,
          [card.x, card.y, card.w, card.h, card.radius, clip.x, clip.y, clip.w, clip.h, clip.radius].allSatisfy({ $0.isFinite }) else { return 0 }
    // Styles: cat, banana, raccoon, effects-only. Refuse partial glyphs/poses.
    let required = style == 1 ? 1 : (petted ? 18 : 15) + (style == 3 ? 0 : 1)
    guard capacity >= UInt(required) else { return 0 }
    var count = 0
    func add(_ kind: Int32, _ texture: Int32, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
             _ red: Float = 1, _ green: Float = 1, _ blue: Float = 1, _ alpha: Float = 1) {
        output[count] = makeDrawCommand(kind: kind, texture: texture,
            rect: WallifyCardRect(x: x, y: y, w: width, h: height, radius: 0), clip: clip,
            red: red, green: green, blue: blue, alpha: alpha, opacity: opacity)
        count += 1
    }
    if style == 0 {
        let region = catRegions[petFrame(time, fps: 3, frames: 5)]
        add(WALLIFY_NEAREST, WALLIFY_CAT_TEXTURE, card.x + (card.w - region.width) / 2, card.y + card.h - region.height - 5,
            region.width, region.height)
        output[0].sx = Float(region.x) / 541
        output[0].sw = Float(region.width) / 541
        output[0].sh = Float(region.height) / 52
    } else if style == 1 {
        add(WALLIFY_NEAREST, WALLIFY_BANANA_TEXTURE, card.x + (card.w - 98) / 2 - 6, card.y + (card.h - 114) / 2, 98, 114)
        output[0].sy = Float(petFrame(time, fps: 24, frames: 45)) / 45
        output[0].sh = 1 / 45
        return UInt(count)
    } else if style == 2 {
        add(WALLIFY_NEAREST, WALLIFY_RACCOON_TEXTURE, floor(card.x + (card.w - 110) / 2), floor(card.y + card.h - 68 - 5), 110, 68)
        output[0].sx = Float(petFrame(time, fps: 3, frames: 5)) / 5
        output[0].sw = 0.2
    }
    let color: (Float, Float, Float, Float) = petted ? (211 / 255, 134 / 255, 155 / 255, 235 / 255) : (235 / 255, 219 / 255, 178 / 255, 210 / 255)
    for index in 0..<3 {
        let value = time / 3.6 + Double(index) / 3
        let remainder = value.truncatingRemainder(dividingBy: 1)
        let phase = remainder < 0 ? remainder + 1 : remainder
        let alpha = min(1, min(phase * 6, (1 - phase) * 4))
        let size = index == 2 ? 2.0 : 1.0
        let x = floor(card.x + (card.w - 110) / 2 + 20 + phase * 23)
        let y = floor(card.y + 105 - phase * 42)
        for (dx, dy, width) in petted ? heartStrips : sleepStrips {
            add(WALLIFY_SOLID, 0, x + Double(dx) * size, y + Double(dy) * size, Double(width) * size, size,
                color.0, color.1, color.2, Float(alpha * Double(color.3)))
        }
    }
    return UInt(count)
}
