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
