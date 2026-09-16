const std = @import("std");
const state = @import("../../state.zig");
const gpu = @import("../canvas.zig");
const text = @import("../text_cache.zig");

const L = state.Layout;
const primary_color: gpu.Color = .{ 245.0 / 255.0, 245.0 / 255.0, 247.0 / 255.0, 1.0 };

fn lerp(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

pub fn drawLabels(canvas: *gpu.Canvas, elapsed: f64) void {
    const title = if (state.global_title_len > 0) state.global_title[0..state.global_title_len] else "Not Playing";
    const artist = if (state.global_artist_len > 0) state.global_artist[0..state.global_artist_len] else "";

    const secondary_color: gpu.Color = .{
        @as(f32, @floatFromInt(@max(145, state.extracted_r))) / 255.0,
        @as(f32, @floatFromInt(@max(145, state.extracted_g))) / 255.0,
        @as(f32, @floatFromInt(@max(145, state.extracted_b))) / 255.0,
        1.0,
    };

    if (state.mode_mix < 0.16) {
        text.draw(canvas, title, L.art_x_expanded, L.card_y + L.mini_title_y, L.mini_text_width, 15.0, 1.0, true, primary_color, state.marquee_offset, false, false);
        text.draw(canvas, artist, L.art_x_expanded, L.card_y + L.mini_artist_y, L.mini_text_width, 11.0, 1.0, false, secondary_color, 0.0, false, true);
        return;
    }

    const t = std.math.clamp((state.mode_mix - 0.16) / 0.84, 0.0, 1.0);
    const x = lerp(L.art_x_expanded, state.layout.bar_x, t);
    const width = lerp(L.mini_text_width, state.layout.bar_w, t);

    text.draw(canvas, title, x, lerp(L.card_y + L.mini_title_y, state.layout.art_y + 6.0, t), width, 17.0, lerp(15.0, 17.0, t) / 17.0, true, primary_color, 0.0, false, true);
    text.draw(canvas, if (artist.len > 0) artist else "Play something to get started", x, lerp(L.card_y + L.mini_artist_y, state.layout.art_y + 30.0, t), width, 14.0, lerp(11.0, 14.0, t) / 14.0, false, secondary_color, 0.0, false, true);

    if (t < 0.88) return;

    var buffer: [32]u8 = undefined;
    const e: u32 = @intFromFloat(@max(0, elapsed));
    const d: u32 = @intFromFloat(@max(0, state.global_duration));

    const e_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ e / 60, e % 60 }) catch return;
    text.draw(canvas, e_text, x, state.layout.bar_y + 11.0, 100.0, 12.0, 1.0, false, secondary_color, 0.0, false, false);

    const d_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ d / 60, d % 60 }) catch return;
    text.draw(canvas, d_text, x, state.layout.bar_y + 11.0, state.layout.bar_w, 12.0, 1.0, false, secondary_color, 0.0, true, false);
}
