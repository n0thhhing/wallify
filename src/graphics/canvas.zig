const std = @import("std");
const native = @import("../platform/native.zig");
pub const Rect = @import("../ui/hitbox.zig").Rect;
pub const Color = [4]f32;
extern fn wallify_init_draw_command(output: *native.DrawCommand, kind: c_int, texture: c_int, rect: *const Rect, clip: *const Rect, color: *const Color, opacity: f32) callconv(.c) void;

pub const Texture = enum(c_int) {
    white,
    artwork,
    previous_artwork,
    glow,
    previous_glow,
    cat = native.gpu.WALLIFY_CAT_TEXTURE,
    banana = native.gpu.WALLIFY_BANANA_TEXTURE,
    spotify,
    play,
    pause,
    previous,
    next,
    raccoon = native.gpu.WALLIFY_RACCOON_TEXTURE,
    text_start,
    // Reserved texture slot: the Swift renderer binds the persistent static-scene render target.
    // It must stay outside the normal texture-upload range.
    cached_scene = native.gpu.WALLIFY_CACHED_SCENE_TEXTURE,
};

pub const Canvas = struct {
    commands: [native.gpu.WALLIFY_MAX_COMMANDS]native.DrawCommand = undefined,
    count: usize = 0,
    clip: Rect,
    opacity: f32 = 1.0,

    pub fn add(self: *Canvas, kind: c_int, texture: c_int, rect: Rect, color: Color) *native.DrawCommand {
        std.debug.assert(self.count < self.commands.len);
        const c = &self.commands[self.count];
        self.count += 1;

        wallify_init_draw_command(c, kind, texture, &rect, &self.clip, &color, self.opacity);
        return c;
    }

    pub fn fill(self: *Canvas, rect: Rect, color: Color) void {
        _ = self.add(native.gpu.WALLIFY_SOLID, 0, rect, color);
    }

    pub fn stroke(self: *Canvas, rect: Rect, width: f64, color: Color) void {
        self.add(native.gpu.WALLIFY_SOLID, 0, rect, color).stroke = @floatCast(width);
    }

    pub fn image(self: *Canvas, texture: Texture, rect: Rect, opacity: f32) void {
        self.imageTint(texture, rect, .{ 1, 1, 1, opacity });
    }

    pub fn imageTint(self: *Canvas, texture: Texture, rect: Rect, color: Color) void {
        _ = self.add(native.gpu.WALLIFY_TEXTURE, @intFromEnum(texture), rect, color);
    }

    pub fn transition(
        self: *Canvas,
        style: @import("../state.zig").TransitionStyle,
        new_tex: Texture,
        old_tex: Texture,
        rect: Rect,
        mix: f32,
        time: f32,
        r: f32,
        g: f32,
        b: f32,
    ) void {
        const kind: c_int = switch (style) {
            .cinematic => native.gpu.WALLIFY_CINEMATIC,
            .ripple => native.gpu.WALLIFY_RIPPLE,
            .flip => native.gpu.WALLIFY_FLIP,
            .vinyl => native.gpu.WALLIFY_VINYL,
            .glitch => native.gpu.WALLIFY_GLITCH,
            .default => return,
        };
        const c = self.add(kind, @intFromEnum(new_tex), rect, .{ r, g, b, 1.0 });
        c.parameter = @floatFromInt(@intFromEnum(old_tex));
        c.sx = mix;
        c.sy = time;
    }

    pub fn cinematic(
        self: *Canvas,
        new_tex: Texture,
        old_tex: Texture,
        rect: Rect,
        mix: f32,
        time: f32,
        r: f32,
        g: f32,
        b: f32,
    ) void {
        self.transition(.cinematic, new_tex, old_tex, rect, mix, time, r, g, b);
    }

    pub fn glass(self: *Canvas, rect: Rect, color: Color, art_r: f32, art_g: f32, art_b: f32, ambient_intensity: f32) void {
        const c = self.add(native.gpu.WALLIFY_GLASS, 0, rect, color);
        c.sx = art_r;
        c.sy = art_g;
        c.sw = art_b;
        c.parameter = ambient_intensity;
    }

    pub fn shadow(self: *Canvas, caster: Rect, blur: f64, offset_x: f64, offset_y: f64, alpha: f32) void {
        const c = self.add(native.gpu.WALLIFY_SHADOW, 0, caster, .{ 0.0, 0.0, 0.0, alpha });
        c.sx = @floatCast(offset_x);
        c.sy = @floatCast(offset_y);
        c.parameter = @floatCast(blur);
    }

    pub fn aurora(self: *Canvas, rect: Rect, primary: [3]f32, secondary: [3]f32, time: f32, alpha: f32) void {
        const c = self.add(native.gpu.WALLIFY_AURORA, 0, rect, .{ primary[0], primary[1], primary[2], alpha });
        c.sx = secondary[0];
        c.sy = secondary[1];
        c.sw = secondary[2];
        c.sh = time;
    }

    pub fn submit(self: *Canvas, width: f64, height: f64) void {
        native.wallify_present(@floatCast(width), @floatCast(height), &self.commands, self.count);
    }

    // Dynamic frames start by sampling the cached static scene, then add only content that can change.
    pub fn compositeCachedScene(self: *Canvas, width: f64, height: f64) void {
        self.image(.cached_scene, .{ .x = 0, .y = 0, .w = width, .h = height }, 1.0);
    }

    // Keep static and dynamic command lists separate so unchanged artwork/glow never re-enters the hot pass.
    pub fn submitSplit(static_canvas: *Canvas, dynamic_canvas: *Canvas, width: f64, height: f64) void {
        native.wallify_present_split(
            @floatCast(width),
            @floatCast(height),
            &static_canvas.commands,
            static_canvas.count,
            &dynamic_canvas.commands,
            dynamic_canvas.count,
        );
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

test "GPU glass and shadow commands configure parameters accurately" {
    var canvas = Canvas{ .clip = .{ .x = 0, .y = 0, .w = 531, .h = 164, .radius = 26 }, .opacity = 1.0 };
    canvas.glass(.{ .x = 0, .y = 0, .w = 531, .h = 164, .radius = 26 }, .{ 0.1, 0.1, 0.1, 1.0 }, 0.8, 0.4, 0.2, 0.15);
    try std.testing.expectEqual(@as(c_int, native.gpu.WALLIFY_GLASS), canvas.commands[0].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), canvas.commands[0].sx, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), canvas.commands[0].parameter, 0.001);

    canvas.shadow(.{ .x = 16, .y = 16, .w = 136, .h = 136, .radius = 14 }, 8.0, 0.0, 3.0, 0.35);
    try std.testing.expectEqual(@as(c_int, native.gpu.WALLIFY_SHADOW), canvas.commands[1].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), canvas.commands[1].parameter, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), canvas.commands[1].sy, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), canvas.commands[1].alpha, 0.001);

    canvas.aurora(.{ .x = 0, .y = 0, .w = 531, .h = 164, .radius = 26 }, .{ 0.9, 0.2, 0.3 }, .{ 0.3, 0.8, 0.9 }, 4.5, 0.4);
    try std.testing.expectEqual(@as(c_int, native.gpu.WALLIFY_AURORA), canvas.commands[2].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), canvas.commands[2].r, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), canvas.commands[2].sx, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), canvas.commands[2].sh, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), canvas.commands[2].alpha, 0.001);
}
