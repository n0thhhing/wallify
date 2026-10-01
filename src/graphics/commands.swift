func makeDrawCommand(kind: Int32, texture: Int32, rect: WallifyCardRect, clip: WallifyCardRect,
                     red: Float, green: Float, blue: Float, alpha: Float, opacity: Float) -> DrawCommand {
    var command = DrawCommand()
    command.kind = kind
    command.texture_id = texture
    command.dx = Float(rect.x); command.dy = Float(rect.y)
    command.dw = Float(rect.w); command.dh = Float(rect.h); command.radius = Float(rect.radius)
    command.sw = 1; command.sh = 1
    command.r = red; command.g = green; command.b = blue; command.alpha = alpha * opacity
    command.clip_x = Float(clip.x); command.clip_y = Float(clip.y)
    command.clip_w = Float(clip.w); command.clip_h = Float(clip.h); command.clip_radius = Float(clip.radius)
    return command
}

@_cdecl("wallify_init_draw_command")
public func initializeDrawCommand(_ output: UnsafeMutablePointer<DrawCommand>?, _ kind: Int32, _ texture: Int32,
                                  _ rect: UnsafePointer<WallifyCardRect>?, _ clip: UnsafePointer<WallifyCardRect>?,
                                  _ color: UnsafePointer<Float>?, _ opacity: Float) {
    guard let output = output, let rect = rect, let clip = clip, let color = color else { return }
    output.pointee = makeDrawCommand(kind: kind, texture: texture, rect: rect.pointee, clip: clip.pointee,
                                    red: color[0], green: color[1], blue: color[2], alpha: color[3], opacity: opacity)
}
