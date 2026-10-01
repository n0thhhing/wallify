import Foundation

enum Texture: Int32 {
    case white = 0, artwork, previousArtwork, glow, previousGlow, cat, banana, spotify
    case play, pause, previous, next, raccoon, textStart
    case cachedScene = 63
}

func cardRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double = 0) -> WallifyCardRect {
    WallifyCardRect(x: x, y: y, w: w, h: h, radius: radius)
}

final class Canvas {
    var commands = [DrawCommand]()
    var clip: WallifyCardRect
    var opacity: Float = 1

    init(clip: WallifyCardRect) { self.clip = clip; commands.reserveCapacity(Int(WALLIFY_MAX_COMMANDS)) }

    @discardableResult func add(_ kind: Int32, _ texture: Int32, _ rect: WallifyCardRect, _ color: SIMD4<Float>) -> Int {
        precondition(commands.count < Int(WALLIFY_MAX_COMMANDS), "Scene exceeds GPU command budget")
        commands.append(makeDrawCommand(kind: kind, texture: texture, rect: rect, clip: clip,
                                         red: color.x, green: color.y, blue: color.z, alpha: color.w, opacity: opacity))
        return commands.count - 1
    }
    func fill(_ rect: WallifyCardRect, _ color: SIMD4<Float>) { add(Int32(WALLIFY_SOLID), 0, rect, color) }
    func stroke(_ rect: WallifyCardRect, _ width: Double, _ color: SIMD4<Float>) {
        let index = add(Int32(WALLIFY_SOLID), 0, rect, color); commands[index].stroke = Float(width)
    }
    func image(_ texture: Texture, _ rect: WallifyCardRect, _ alpha: Float = 1) { imageTint(texture, rect, SIMD4(1, 1, 1, alpha)) }
    func imageTint(_ texture: Texture, _ rect: WallifyCardRect, _ color: SIMD4<Float>) { add(Int32(WALLIFY_TEXTURE), texture.rawValue, rect, color) }
    func transition(_ style: UInt8, _ rect: WallifyCardRect, _ mix: Float, _ time: Float, _ color: SIMD3<Float>, brightness: Float = 1) {
        guard style > 0, style <= 5 else { return }
        let index = add(Int32(WALLIFY_CINEMATIC) + Int32(style) - 1, Texture.artwork.rawValue, rect, SIMD4(color.x, color.y, color.z, 1))
        commands[index].parameter = Float(Texture.previousArtwork.rawValue)
        commands[index].sx = mix; commands[index].sy = time
        commands[index].sh = brightness
    }
    func glass(_ rect: WallifyCardRect, _ color: SIMD4<Float>, _ art: SIMD3<Float>, _ intensity: Float) {
        let index = add(Int32(WALLIFY_GLASS), 0, rect, color)
        commands[index].sx = art.x; commands[index].sy = art.y; commands[index].sw = art.z; commands[index].parameter = intensity
    }
    func aurora(_ rect: WallifyCardRect, _ color: SIMD3<Float>, _ time: Float, _ alpha: Float) {
        let index = add(Int32(WALLIFY_AURORA), 0, rect, SIMD4(color.x, color.y, color.z, alpha))
        commands[index].sx = color.x; commands[index].sy = color.y; commands[index].sw = color.z; commands[index].sh = time
    }
    func pet(_ style: Int32, _ card: WallifyCardRect, _ time: Double, _ petted: Bool) {
        var card = card, clip = clip
        var output = [DrawCommand](repeating: DrawCommand(), count: 19)
        let count = output.withUnsafeMutableBufferPointer { drawPet(style, &card, &clip, time, petted, opacity, $0.baseAddress, UInt($0.count)) }
        precondition(commands.count + Int(count) <= Int(WALLIFY_MAX_COMMANDS))
        commands.append(contentsOf: output.prefix(Int(count)))
    }
}
