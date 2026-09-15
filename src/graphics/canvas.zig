const std = @import("std");
const native = @import("../platform/native.zig");
pub const Rect = @import("../ui/hitbox.zig").Rect;
pub const Color = [4]f32;
pub const Texture = enum(c_int) { white, artwork, previous_artwork, glow, previous_glow, cat, banana, spotify, play, pause, previous, next, text_start };
pub const Canvas = struct {
    commands: [native.gpu.WALLIFY_MAX_COMMANDS]native.DrawCommand = undefined,
    count: usize = 0,
    clip: Rect,
    opacity: f32 = 1,

    pub fn add(self: *Canvas, kind: c_int, texture: c_int, rect: Rect, color: Color) *native.DrawCommand {
        // Capacity covers the complete scene (including all sleep marks).
        std.debug.assert(self.count < self.commands.len);
        const c = &self.commands[self.count];
        self.count += 1;
        c.* = std.mem.zeroes(native.DrawCommand);
        c.kind = kind;
        c.texture_id = texture;
        c.dx = @floatCast(rect.x);
        c.dy = @floatCast(rect.y);
        c.dw = @floatCast(rect.w);
        c.dh = @floatCast(rect.h);
        c.radius = @floatCast(rect.radius);
        c.sw = 1;
        c.sh = 1;
        c.r = color[0];
        c.g = color[1];
        c.b = color[2];
        c.alpha = color[3] * self.opacity;
        c.clip_x = @floatCast(self.clip.x);
        c.clip_y = @floatCast(self.clip.y);
        c.clip_w = @floatCast(self.clip.w);
        c.clip_h = @floatCast(self.clip.h);
        c.clip_radius = @floatCast(self.clip.radius);
        return c;
    }
    pub fn fill(self: *Canvas, rect: Rect, color: Color) void {
        _ = self.add(native.gpu.WALLIFY_SOLID, 0, rect, color);
    }
    pub fn stroke(self: *Canvas, rect: Rect, width: f64, color: Color) void {
        self.add(native.gpu.WALLIFY_SOLID, 0, rect, color).stroke = @floatCast(width);
    }
    pub fn image(self: *Canvas, texture: Texture, rect: Rect, opacity: f32) void {
        _ = self.add(native.gpu.WALLIFY_TEXTURE, @intFromEnum(texture), rect, .{ 1, 1, 1, opacity });
    }
    pub fn submit(self: *Canvas, width: f64, height: f64) void {
        native.wallify_present(@floatCast(width), @floatCast(height), &self.commands, self.count);
    }
};

test "GPU command preserves clipping and premultiplied opacity contract" {
    var canvas = Canvas{ .clip = .{ .x = 8, .y = 35, .w = 164, .h = 164, .radius = 26 }, .opacity = 0.5 };
    canvas.fill(.{ .x = 1, .y = 2, .w = 10, .h = 12, .radius = 3 }, .{ 1, 0, 0, 0.6 });
    const c = canvas.commands[0];
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), c.alpha, 0.0001);
    try std.testing.expectEqual(@as(f32, 8), c.clip_x);
    try std.testing.expectEqual(@as(f32, 26), c.clip_radius);
    try std.testing.expectEqual(@as(f32, 3), c.radius);
}

test "both pets emit clipped GPU commands within the scene budget" {
    const card = Rect{ .x = 0, .y = 0, .w = 531, .h = 164, .radius = 26 };
    var cat = Canvas{ .clip = card };
    @import("pets/idle_cat.zig").draw(&cat, card, 0.7);
    try std.testing.expectEqual(@as(usize, 40), cat.count);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(Texture.cat)), cat.commands[0].texture_id);
    for (cat.commands[0..cat.count]) |c| try std.testing.expectEqual(@as(f32, 26), c.clip_radius);
    var banana = Canvas{ .clip = card };
    @import("pets/banana_cat.zig").draw(&banana, card, 1.0);
    try std.testing.expectEqual(@as(usize, 1), banana.count);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0 / 45.0), banana.commands[0].sy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 45.0), banana.commands[0].sh, 0.0001);
}
