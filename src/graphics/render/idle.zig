const std = @import("std");
const state = @import("../../state.zig");
const gpu = @import("../canvas.zig");
const text = @import("../text_cache.zig");

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
        .raccoon => @import("../pets/idle_raccoon.zig").draw(canvas, card, state.cat_time, state.animation_time < state.cat_pet_until),
        .spotify => drawSpotifyLauncher(canvas, card),
    }
}

fn drawSpotifyLauncher(canvas: *gpu.Canvas, card: gpu.Rect) void {
    const compact = state.layout.compact_mix > 0.5;
    const size = if (compact) card.w else state.layout.art_size;
    const padded = size * 128.0 / 104.0;
    const inset = (padded - size) / 2.0;

    const icon_rect = gpu.Rect{
        .x = state.layout.art_x - inset,
        .y = state.layout.art_y - inset,
        .w = padded,
        .h = padded,
    };
    canvas.image(.spotify, icon_rect, 1.0);

    if (!compact) {
        text.draw(canvas, "Open Spotify", state.layout.text_x, state.layout.title_y, state.layout.text_width, 17.0, 1.0, true, primary_color, 0.0, false, true);
        text.draw(canvas, "Click to launch", state.layout.text_x, state.layout.artist_y, state.layout.text_width, 13.0, 1.0, false, subtitle_color, 0.0, false, true);
    }
}

test "pets emit clipped GPU commands within the scene budget" {
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

    for ([_]bool{ false, true }) |petted| {
        for (0..5) |frame| {
            var raccoon = gpu.Canvas{ .clip = card };
            @import("../pets/idle_raccoon.zig").draw(&raccoon, card, (@as(f64, @floatFromInt(frame)) + 0.5) / 3.0, petted);
            try std.testing.expectEqual(@as(usize, if (petted) 49 else 40), raccoon.count);
            try std.testing.expectEqual(@as(c_int, @intFromEnum(gpu.Texture.raccoon)), raccoon.commands[0].texture_id);
            try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(frame)) / 5, raccoon.commands[0].sx, 0.0001);
            try std.testing.expectApproxEqAbs(@as(f32, 0.2), raccoon.commands[0].sw, 0.0001);
            for (raccoon.commands[0..raccoon.count]) |c| {
                try std.testing.expectEqual(@as(f32, 26), c.clip_radius);
                try std.testing.expect(c.dy + c.dh <= card.h);
            }
        }
    }
}

test "raccoon breathing matches the cat cadence" {
    const raccoon = @import("../pets/idle_raccoon.zig");
    try std.testing.expectEqual(@as(usize, 0), raccoon.frameAt(0));
    for (0..30) |tick| {
        const time = (@as(f64, @floatFromInt(tick)) + 0.5) / 3.0;
        try std.testing.expectEqual(tick % 5, raccoon.frameAt(time));
    }
    try std.testing.expectEqual(@as(usize, 4), raccoon.frameAt(1.66));
    try std.testing.expectEqual(@as(usize, 0), raccoon.frameAt(1.67));
}
