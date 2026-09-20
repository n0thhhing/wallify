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
    if (state.setting_hide_text) return;

    const compact_mix = std.math.clamp(state.layout.compact_mix, 0.0, 1.0);
    const expanded_mix = 1.0 - compact_mix;
    const scale: f64 = switch (state.setting_font_scale) {
        .small => 0.85,
        .normal => 1.0,
        .large => 1.15,
    };

    const title = if (state.global_title_len > 0) state.global_title[0..state.global_title_len] else "Not Playing";
    const artist = if (state.global_artist_len > 0) state.global_artist[0..state.global_artist_len] else "";

    const secondary_color: gpu.Color = .{
        @as(f32, @floatFromInt(@max(145, state.extracted_r))) / 255.0,
        @as(f32, @floatFromInt(@max(145, state.extracted_g))) / 255.0,
        @as(f32, @floatFromInt(@max(145, state.extracted_b))) / 255.0,
        1.0,
    };

    if (compact_mix > 0.84) {
        text.draw(
            canvas,
            title,
            state.layout.text_x,
            state.layout.title_y,
            state.layout.text_width,
            15.0 * scale,
            1.0,
            true,
            primary_color,
            state.marquee_offset,
            false,
            false,
        );
        text.draw(
            canvas,
            artist,
            state.layout.text_x,
            state.layout.artist_y,
            state.layout.text_width,
            11.0 * scale,
            1.0,
            false,
            secondary_color,
            0.0,
            false,
            true,
        );
        return;
    }

    const title_size = lerp(15.0, 17.0, expanded_mix) * scale;
    const artist_size = lerp(11.0, 14.0, expanded_mix) * scale;

    text.draw(
        canvas,
        title,
        state.layout.text_x,
        state.layout.title_y,
        state.layout.text_width,
        title_size,
        lerp(15.0, 17.0, expanded_mix) / 17.0,
        true,
        primary_color,
        0.0,
        false,
        true,
    );
    text.draw(
        canvas,
        if (artist.len > 0) artist else "Play something to get started",
        state.layout.text_x,
        state.layout.artist_y,
        state.layout.text_width,
        artist_size,
        lerp(11.0, 14.0, expanded_mix) / 14.0,
        false,
        secondary_color,
        0.0,
        false,
        true,
    );

    if (expanded_mix < 0.88 or !state.setting_show_timestamps) return;

    var buffer: [32]u8 = undefined;
    const e: u32 = @intFromFloat(@max(0, elapsed));
    const d: u32 = @intFromFloat(@max(0, state.global_duration));

    const e_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ e / 60, e % 60 }) catch return;
    text.draw(
        canvas,
        e_text,
        state.layout.text_x,
        state.layout.timestamp_y,
        100.0,
        12.0 * scale,
        1.0,
        false,
        secondary_color,
        0.0,
        false,
        false,
    );

    const d_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ d / 60, d % 60 }) catch return;
    text.draw(
        canvas,
        d_text,
        state.layout.text_x,
        state.layout.timestamp_y,
        state.layout.text_width,
        12.0 * scale,
        1.0,
        false,
        secondary_color,
        0.0,
        true,
        false,
    );
}
