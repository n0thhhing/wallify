const std = @import("std");
const state = @import("../../state.zig");
const gpu = @import("../canvas.zig");
const text = @import("../text_cache.zig");

const L = state.Layout;
const primary_color: gpu.Color = .{ 245.0 / 255.0, 245.0 / 255.0, 247.0 / 255.0, 1.0 };
const subtitle_color: gpu.Color = .{ 0.62, 0.60, 0.57, 1.0 };
const idle_card_bg: gpu.Color = .{ 30.0 / 255.0, 29.0 / 255.0, 32.0 / 255.0, 1.0 };

pub fn drawIdle(canvas: *gpu.Canvas, card: gpu.Rect) void {
    // Opaque idle background provides the group crossfade without a CPU underlay.
    canvas.opacity = @floatCast(state.idle_mix);
    canvas.fill(card, idle_card_bg);

    switch (state.setting_idle_style) {
        .pixel_cat => @import("../pets/idle_cat.zig").draw(canvas, card, state.cat_time, state.animation_time < state.cat_pet_until),
        .banana_cat => @import("../pets/banana_cat.zig").draw(canvas, card, state.cat_time),
        .spotify => drawSpotifyLauncher(canvas, card),
    }
}

fn drawSpotifyLauncher(canvas: *gpu.Canvas, card: gpu.Rect) void {
    const compact = state.mode_mix < 0.5;
    const size = if (compact) card.w else L.art_size_expanded;
    const padded = size * 128.0 / 104.0;
    const inset = (padded - size) / 2.0;

    const icon_rect = gpu.Rect{
        .x = (if (compact) card.x else L.art_x_expanded) - inset,
        .y = (if (compact) card.y else L.art_y_expanded) - inset,
        .w = padded,
        .h = padded,
    };
    canvas.image(.spotify, icon_rect, 1.0);

    if (!compact) {
        text.draw(canvas, "Open Spotify", state.layout.bar_x, L.art_y_expanded + 36.0, state.layout.bar_w, 17.0, 1.0, true, primary_color, 0.0, false, true);
        text.draw(canvas, "Click to launch", state.layout.bar_x, L.art_y_expanded + 63.0, state.layout.bar_w, 13.0, 1.0, false, subtitle_color, 0.0, false, true);
    }
}

test "both pets emit clipped GPU commands within the scene budget" {
    const card = gpu.Rect{ .x = 0, .y = 0, .w = 531, .h = 164, .radius = 26 };
    var cat = gpu.Canvas{ .clip = card };
    @import("../pets/idle_cat.zig").draw(&cat, card, 0.7, false);
    try std.testing.expectEqual(@as(usize, 40), cat.count);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(gpu.Texture.cat)), cat.commands[0].texture_id);
    for (cat.commands[0..cat.count]) |c| try std.testing.expectEqual(@as(f32, 26), c.clip_radius);

    var banana = gpu.Canvas{ .clip = card };
    @import("../pets/banana_cat.zig").draw(&banana, card, 1.0);
    try std.testing.expectEqual(@as(usize, 1), banana.count);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0 / 45.0), banana.commands[0].sy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 45.0), banana.commands[0].sh, 0.0001);
}
