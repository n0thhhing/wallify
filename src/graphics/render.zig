const std = @import("std");
const state = @import("../state.zig");
pub const PixelEngine = @import("pixel_engine.zig").PixelEngine;
const icon_transition = @import("icon_transition.zig");
const text_renderer = @import("text.zig");
const symbols = @import("symbols.zig");
const glow = @import("glow.zig");
const window = @import("../ui/window.zig");

var render_canvas_buffer: []u32 = &.{};
var shared_frame_id: u64 = 0;

var idle_underlay: []u32 = &.{};
fn publishFrame(engine: *PixelEngine, wide: bool) void {
    var commands: [16]@import("../platform/native.zig").DrawCommand = undefined;
    var cmd_count: usize = 0;
    if (state.idle_mix > 0) {
        const mix = state.idle_mix;
        if (mix < 1) @memcpy(idle_underlay[0..engine.pixels.len], engine.pixels);
        @memset(engine.pixels, 0);
        const x: isize = @intFromFloat(8 * (1 - state.mode_mix));
        const w: isize = @intFromFloat(164 + (state.layout.width - 164) * state.mode_mix);
        engine.fillRoundedRect(x, 35, w, 164, 26, 30, 29, 32, 255);
        switch (state.setting_idle_style) {
            .pixel_cat => @import("pets/idle_cat.zig").draw(engine, x, 35, w, state.cat_time, false, 0, false, &commands, &cmd_count),
            .banana_cat => @import("pets/banana_cat.zig").draw(engine, x, 35, 164, state.cat_time),
            .spotify => {
                const sc = @as(f64, @floatFromInt(engine.scale));
                if (state.mode_mix < 0.5) {
                    // Entire compact widget tile IS the Spotify app icon
                    const full_sz: f64 = 164.0 * (128.0 / 104.0);
                    const offset: f64 = (full_sz - 164.0) / 2.0;
                    const draw_x = @as(f64, @floatFromInt(x)) - offset;
                    const draw_y = 35.0 - offset;
                    _ = symbols.widget_spotify_icon(engine.pixels.ptr, engine.width, engine.height, draw_x * sc, draw_y * sc, full_sz * sc);
                } else {
                    const icon_sz: f64 = 136.0 * (128.0 / 104.0);
                    const offset: f64 = (icon_sz - 136.0) / 2.0;
                    const draw_x: f64 = 24.0 - offset;
                    const draw_y: f64 = 49.0 - offset;
                    _ = symbols.widget_spotify_icon(engine.pixels.ptr, engine.width, engine.height, draw_x * sc, draw_y * sc, icon_sz * sc);
                    drawText(engine, "Open Spotify", 210, 85, state.layout.bar_w, 17, true, false, .{ 240, 235, 225 });
                    drawText(engine, "Click to launch", 210, 112, state.layout.bar_w, 13, false, false, .{ 159, 153, 145 });
                }
            },
        }
        engine.widgetFrame(x, 35, w, 164, 26, state.setting_frame.multiplier());
        engine.clipOutsideRoundedRect(x, 35, w, 164, 26);
        if (mix < 1) {
            const weight: u32 = @intFromFloat(mix * 256);
            for (engine.pixels, idle_underlay[0..engine.pixels.len]) |*pixel, old| {
                var blended: u32 = 0;
                inline for (0..4) |channel| {
                    const shift = channel * 8;
                    blended |= ((((old >> shift) & 255) * (256 - weight) + ((pixel.* >> shift) & 255) * weight) >> 8) << shift;
                }
                pixel.* = blended;
            }
        }
    }
    // `t=f` asks the sandboxed Kitty app to open a path in our temporary
    // directory, which macOS can reject. Kitty's graphics protocol explicitly
    // supports `t=s`: a POSIX shared-memory object that it opens and consumes.
    // It carries the raw frame without a filesystem permission boundary.
    state.current_image_id = if (state.current_image_id == 1) @as(u32, 2) else @as(u32, 1);
    var name_buffer: [64]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buffer, "/wlfy-{d}", .{state.current_image_id}) catch return;
    const bytes = std.mem.sliceAsBytes(engine.pixels);

    // Always unlink first in case a previous run left this exact ID behind
    // without Kitty consuming and unlinking it.
    _ = std.c.shm_unlink(name.ptr);

    const fd = std.c.shm_open(name.ptr, 0x0200 | 0x0800 | 0x0002, @as(std.posix.mode_t, 0o600)); // O_CREAT | O_EXCL | O_RDWR
    if (fd < 0) return;
    defer _ = std.posix.system.close(fd);
    if (std.posix.system.ftruncate(fd, @intCast(bytes.len)) != 0) return;

    const memory = std.posix.mmap(null, bytes.len, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0) catch return;
    defer std.posix.munmap(memory);

    @memcpy(memory, bytes);
    var encoded_name: [160]u8 = undefined;
    const encoded_len = std.base64.standard.Encoder.calcSize(name.len);
    const payload = std.base64.standard.Encoder.encode(encoded_name[0..encoded_len], name);

    const old_image_id: u32 = if (state.current_image_id == 1) 2 else 1;

    std.debug.print("\x1b[H", .{});
    const cols: usize = if (state.desktop_mode) @intFromFloat(state.layout.cells_x) else if (wide) 112 else 70;
    const rows: usize = if (state.desktop_mode) @intFromFloat(state.layout.cells_y) else if (wide) 12 else 24;

    if (std.c.getenv("TMUX") != null) {
        std.debug.print("\x1bPtmux;\x1b\x1b_Ga=T,C=1,f=32,s={d},v={d},c={d},r={d},p=1,i={d},z=-1,t=s,S={d};{s}\x1b\x1b\\\x1b\\", .{ engine.width, engine.height, cols, rows, state.current_image_id, bytes.len, payload });
        std.debug.print("\x1bPtmux;\x1b\x1b_Ga=d,d=i,i={d}\x1b\x1b\\\x1b\\", .{old_image_id});
    } else {
        std.debug.print("\x1b_Ga=T,C=1,f=32,s={d},v={d},c={d},r={d},p=1,i={d},z=-1,t=s,S={d};{s}\x1b\\", .{ engine.width, engine.height, cols, rows, state.current_image_id, bytes.len, payload });
        std.debug.print("\x1b_Ga=d,d=i,i={d}\x1b\\", .{old_image_id});
    }
}

pub fn drawText(engine: *PixelEngine, text: []const u8, x: f64, y: f64, width: f64, size: f64, bold: bool, right: bool, color: [3]u8) void {
    text_renderer.widget_text(engine.pixels.ptr, engine.width, engine.height, text.ptr, text.len, x * state.render_scale, y * state.render_scale, width * state.render_scale, size * state.render_scale, @intFromBool(bold), @intFromBool(right), color[0], color[1], color[2]);
}

fn drawMarqueeText(engine: *PixelEngine, text: []const u8, x: f64, y: f64, viewport_width: f64, offset: f64, color: [3]u8) void {
    const scale: f64 = @floatFromInt(state.render_scale);
    text_renderer.widget_text_clipped(engine.pixels.ptr, engine.width, engine.height, text.ptr, text.len, (x - offset) * scale, y * scale, x * scale, viewport_width * scale, 15 * state.render_scale, 1, color[0], color[1], color[2]);
}

fn lerp(a: f64, b: f64, amount: f64) f64 {
    return a + (b - a) * amount;
}

fn drawTextOverlays(engine: *PixelEngine, debug_x: isize, debug_y: isize, displayed_elapsed: f64) void {
    const primary = [3]u8{ 245, 245, 247 };
    const secondary = [3]u8{ @max(145, state.extracted_r), @max(145, state.extracted_g), @max(145, state.extracted_b) };
    const title = if (state.global_title_len > 0) state.global_title[0..state.global_title_len] else "Not Playing";
    const artist = if (state.global_artist_len > 0) state.global_artist[0..state.global_artist_len] else "";
    const card_y: f64 = 35;
    // The compact caption travels with the artwork rather than being replaced
    // at a threshold.  It gives the mode change one continuous focal point.
    if (state.mode_mix < 0.16) {
        const mini_card_y: isize = @intFromFloat(card_y);
        drawMarqueeText(engine, title, 24, @floatFromInt(mini_card_y + 116), 132, state.marquee_offset, primary);
        drawText(engine, artist, 24, @floatFromInt(mini_card_y + 137), 132, 11, false, false, secondary);
        return;
    }
    const travel = @min(1.0, @max(0.0, (state.mode_mix - 0.16) / 0.84));
    const text_x = lerp(24, state.layout.bar_x, travel);
    const title_y = lerp(card_y + 116, state.layout.art_y + 8, travel);
    const artist_y = lerp(card_y + 137, state.layout.art_y + 32, travel);
    const text_width = lerp(132, state.layout.bar_w, travel);
    const title_size = lerp(15, 17, travel);
    const artist_size = lerp(11, 14, travel);
    drawText(engine, title, text_x, title_y, text_width, title_size, true, false, primary);
    drawText(engine, if (artist.len > 0) artist else "Play something to get started", text_x, artist_y, text_width, artist_size, false, false, secondary);
    if (travel < 0.88) return;
    var time_buf: [32]u8 = undefined;
    const elapsed: u32 = @intFromFloat(@max(0, displayed_elapsed));
    const duration: u32 = @intFromFloat(@max(0, state.global_duration));
    const elapsed_text = std.fmt.bufPrint(&time_buf, "{d}:{d:0>2}", .{ elapsed / 60, elapsed % 60 }) catch "0:00";
    drawText(engine, elapsed_text, text_x, state.layout.bar_y + 13, 100, 12, false, false, secondary);
    const duration_text = std.fmt.bufPrint(&time_buf, "{d}:{d:0>2}", .{ duration / 60, duration % 60 }) catch "0:00";
    drawText(engine, duration_text, text_x, state.layout.bar_y + 13, state.layout.bar_w, 12, false, true, secondary);

    _ = debug_x;
    _ = debug_y;
}

pub fn drawUIFrame() void {
    window.widget_render_lock();
    defer window.widget_render_unlock();
    const columns = window.widget_terminal_columns();
    const wide = !state.desktop_mode and (columns == 0 or columns >= 112);
    if (state.desktop_mode) {
        state.layout.cells_x = @floatFromInt(@max(1, columns));
        state.layout.cells_y = @floatFromInt(@max(1, window.widget_terminal_rows()));
        const display_w = window.widget_cell_width() * state.layout.cells_x;
        const display_h = window.widget_cell_height() * state.layout.cells_y;
        // During a mode morph, use the dimensions of the *current* Kitty
        // surface. Switching to compact no longer changes scale before the
        // panel itself has narrowed, which removes the size pop at the end.
        const surface_is_compact = display_w > 0 and display_w < 400;
        // Both modes place their visible card at y=35.  The expanded surface
        // is taller solely to contain that card, keeping its top edge on the
        // same desktop-widget row as the compact tile.
        state.layout.height = if (surface_is_compact) 224 else 199;
        if (display_w > 0 and display_h > 0) {
            state.layout.width = @floor(state.layout.height * display_w / display_h + 0.5);
            state.layout.bar_w = @max(80, state.layout.width - state.layout.bar_x - 30);
            const center = state.layout.bar_x + state.layout.bar_w / 2;
            state.layout.buttons[0].x = center - 41;
            state.layout.buttons[1].x = center;
            state.layout.buttons[2].x = center + 41;
        }
    }
    // Reapply the selected density on every render so terminal resizing never
    // leaves stale hitboxes behind.
    state.layout.art_x = lerp(8, 24, state.mode_mix);
    // Keep the cover and its overlay inside the mini card as that card moves
    // down to line up with the desktop widget grid.
    // The expanded card is only 164 points tall.  Keep the cover and controls
    // inside that physical card while preserving the full-cover compact tile.
    state.layout.art_y = lerp(35, 49, state.mode_mix);
    state.layout.art_size = lerp(164, 136, state.mode_mix);
    state.layout.bar_x = 210;
    state.layout.bar_y = 105;
    state.layout.bar_w = @max(80, state.layout.width - state.layout.bar_x - 30);
    const center = state.layout.bar_x + state.layout.bar_w / 2;
    state.layout.buttons[0].x = center - 41;
    state.layout.buttons[1].x = center;
    state.layout.buttons[2].x = center + 41;
    for (&state.layout.buttons) |*button| button.y = 142;
    const canvas_w: usize = if (state.desktop_mode) @intFromFloat(state.layout.width) else if (wide) 960 else 600;
    const canvas_h: usize = if (state.desktop_mode) @intFromFloat(state.layout.height) else if (wide) 200 else 400;
    if (state.previous_canvas_width != canvas_w) {
        std.debug.print("\x1b[2J\x1b[H", .{});
        state.previous_canvas_width = canvas_w;
    }
    const total_pixels = canvas_w * state.render_scale * canvas_h * state.render_scale;
    if (total_pixels > render_canvas_buffer.len) {
        if (render_canvas_buffer.len > 0) std.heap.page_allocator.free(render_canvas_buffer);
        if (idle_underlay.len > 0) std.heap.page_allocator.free(idle_underlay);
        render_canvas_buffer = std.heap.page_allocator.alloc(u32, total_pixels) catch return;
        idle_underlay = std.heap.page_allocator.alloc(u32, total_pixels) catch return;
    }
    var engine = PixelEngine{
        .scale = state.render_scale,
        .width = canvas_w * state.render_scale,
        .height = canvas_h * state.render_scale,
        .pixels = render_canvas_buffer[0..total_pixels],
    };
    @memset(engine.pixels, 0);

    if (state.idle_mix >= 1) return publishFrame(&engine, wide);

    const displayed_elapsed = if (state.global_is_dragging) state.global_elapsed else state.playback_clock.position(window.widget_monotonic_time(), state.global_duration);
    const t = state.global_anim_art_t;
    const inv = 1.0 - t;
    const ease = 1.0 - (inv * inv * inv);

    const center_x = state.layout.art_x + (state.layout.art_size / 2.0);
    const center_y = state.layout.art_y + (state.layout.art_size / 2.0);
    const min_size = state.layout.art_size - 20.0;

    const raw_size = min_size + (20.0 * ease);
    const half_size = @as(isize, @intFromFloat((raw_size / 2.0) + 0.5));
    const art_size_draw = half_size * 2;

    const c_x_i = @as(isize, @intFromFloat(center_x));
    const c_y_i = @as(isize, @intFromFloat(center_y));
    const art_offset_x = c_x_i - half_size;
    const art_offset_y = c_y_i - half_size;

    const wi = @as(isize, @intFromFloat(lerp(164, state.layout.width, state.mode_mix)));
    // Both modes share the same grid-row top inset.
    const hi: isize = 164;
    const card_y: isize = 35;
    const card_x: isize = @intFromFloat(lerp(8, 0, state.mode_mix));
    engine.fillRoundedRect(card_x, card_y, wi, hi, 26, 28, 28, 30, 255);
    if (state.setting_glow) {
        glow.widget_artwork_glow(engine.pixels.ptr, engine.width, engine.height, state.layout.width, state.layout.height, state.render_scale, ease * state.setting_intensity.multiplier(), state.animation_time, @intFromBool(state.setting_animations));
    }
    const base_radius = lerp(26.0, 14.0, state.mode_mix);
    const inset = (state.layout.art_size - raw_size) / 2.0;
    const radius_reduction = inset * (1.0 - state.mode_mix);
    const art_corner_radius: isize = @intFromFloat(@max(0.0, base_radius - radius_reduction));
    if (state.global_has_artwork) {
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/art.bmp", .{ .ACCMODE = .RDONLY }, 0) catch -1;
        if (fd >= 0) {
            defer _ = std.posix.system.close(fd);
            var stat_info: std.posix.Stat = undefined;
            if (std.posix.system.fstat(fd, &stat_info) == 0 and stat_info.size > 0) {
                const size = @as(usize, @intCast(stat_info.size));
                const buf = std.heap.page_allocator.alloc(u8, size) catch return;
                defer std.heap.page_allocator.free(buf);
                _ = std.posix.read(fd, buf) catch 0;

                const now_art = state.animation_time;
                if (!std.mem.eql(u8, state.cached_art, buf)) {
                    if (state.previous_art.len > 0) std.heap.page_allocator.free(state.previous_art);
                    state.previous_art = state.cached_art;
                    state.cached_art = std.heap.page_allocator.dupe(u8, buf) catch return;
                    state.art_transition_until = if (state.setting_animations and state.previous_art.len > 0) now_art + 0.5 else 0;
                }
                if (now_art < state.art_transition_until and state.previous_art.len > 0) {
                    engine.blitBMP(state.previous_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
                    const old_pixels = std.heap.page_allocator.dupe(u32, engine.pixels) catch return;
                    defer std.heap.page_allocator.free(old_pixels);
                    engine.blitBMP(state.cached_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
                    const progress = @min(1, @max(0, 1 - (state.art_transition_until - now_art) / 0.5));
                    const weight: u32 = @intFromFloat(progress * progress * progress * (10 + progress * (-15 + 6 * progress)) * 256);
                    for (engine.pixels, old_pixels) |*pixel, old| {
                        var mixed: u32 = 0;
                        inline for (0..4) |channel| {
                            const shift = channel * 8;
                            const a = (old >> shift) & 255;
                            const b = (pixel.* >> shift) & 255;
                            mixed |= ((a * (256 - weight) + b * weight) >> 8) << shift;
                        }
                        pixel.* = mixed;
                    }
                } else {
                    engine.blitBMP(state.cached_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
                }
                // Compact has one stable outer widget rim. Do not add a
                // second rim around the shrinking paused artwork.
                if (state.mode_mix >= 0.5) engine.strokeRoundedRect(art_offset_x, art_offset_y, art_size_draw, art_size_draw, art_corner_radius, 0.5, 255, 255, 255, 28);
                const dim_alpha: u8 = @intFromFloat(if (state.setting_dim) 102.0 * (1.0 - ease) else 0);
                if (dim_alpha > 0) {
                    engine.fillRoundedRect(art_offset_x, art_offset_y, art_size_draw, art_size_draw, art_corner_radius, 0, 0, 0, dim_alpha);
                }
            }
        }
    } else {
        // Empty art placeholder
        engine.fillRoundedRect(art_offset_x, art_offset_y, art_size_draw, art_size_draw, art_corner_radius, 40, 40, 45, 255);
    }

    // Keep one macOS widget rim above the artwork for the entire morph.
    // Drawing it here prevents the cover from painting over it in mini mode.
    engine.widgetFrame(card_x, card_y, wi, hi, 26, state.setting_frame.multiplier());

    if (state.mode_mix < 0.5) {
        engine.bottomScrim(card_x, card_y + 84, wi, hi - 84, 0, 162);
        drawTextOverlays(&engine, if (wide) 650 else 24, if (wide) 20 else 220, displayed_elapsed);
        engine.clipOutsideRoundedRect(card_x, card_y, wi, hi, 26);
        return publishFrame(&engine, wide);
    }

    const b_bg: u8 = 45;
    const b_fg: u8 = 255;
    engine.scale = 1;
    const bar_scale = @as(f64, state.render_scale);
    const animated_bar_height = state.layout.bar_h + 4 * state.seek_expansion;
    const bar_x_i = @as(isize, @intFromFloat(state.layout.bar_x * bar_scale));
    const bar_y_i = @as(isize, @intFromFloat((state.layout.bar_y - (animated_bar_height - state.layout.bar_h) / 2) * bar_scale));
    const bar_w_i = @as(isize, @intFromFloat(state.layout.bar_w * bar_scale));
    const bar_h_i = @as(isize, @intFromFloat(animated_bar_height * bar_scale));
    const b_rad = @divTrunc(bar_h_i, 2);

    engine.fillRoundedRect(bar_x_i, bar_y_i, bar_w_i, bar_h_i, b_rad, b_bg, b_bg, b_bg, 255);
    if (state.global_duration > 0.0) {
        var pct = displayed_elapsed / state.global_duration;
        if (pct < 0.0) pct = 0.0;
        if (pct > 1.0) pct = 1.0;
        engine.fillProgress(bar_x_i, bar_y_i, state.layout.bar_w * pct * bar_scale, state.layout.bar_w * bar_scale, bar_h_i, b_fg);
    }

    engine.scale = state.render_scale;

    for (state.layout.buttons, 0..) |button, index| {
        const hover = state.hover_amount[index];
        if (hover > 0.01) {
            const bounds = button.bounds();
            engine.fillRoundedRect(@intFromFloat(bounds.x), @intFromFloat(bounds.y), @intFromFloat(bounds.w), @intFromFloat(bounds.h), @intFromFloat(bounds.radius), 255, 255, 255, @intFromFloat(hover * 31));
        }
        var icon_kind: symbols.IconKind = switch (button.id) {
            .PlayPause => if (state.global_rate > 0) .pause else .play,
            .Prev => .prev,
            .Next => .next,
        };
        var icon_scale: f64 = 1;
        if (button.id == .PlayPause) {
            icon_kind = if (state.play_pause_mix < 0.5) .play else .pause;
            icon_scale = icon_transition.scale(state.play_pause_mix, state.global_rate > 0);
        }
        if (icon_scale > 0.001) symbols.widget_icon(engine.pixels.ptr, engine.width, engine.height, button.x * state.render_scale, button.y * state.render_scale, icon_kind, hover, 1, icon_scale * state.render_scale);
    }

    drawTextOverlays(&engine, if (wide) 650 else 24, if (wide) 20 else 220, displayed_elapsed);

    if (state.desktop_mode) engine.clipOutsideRoundedRect(card_x, card_y, wi, hi, 26);
    publishFrame(&engine, wide);
}

pub fn extractColor() void {
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/art.bmp", .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer _ = std.posix.system.close(fd);
    var stat_info: std.posix.Stat = undefined;
    if (std.posix.system.fstat(fd, &stat_info) != 0 or stat_info.size <= 54) return;
    const size = @as(usize, @intCast(stat_info.size));
    const buf = std.heap.page_allocator.alloc(u8, size) catch return;
    defer std.heap.page_allocator.free(buf);

    const n = std.posix.read(fd, buf) catch 0;
    if (n <= 54) return;

    const pixels = buf[54..n];
    var r: usize = 0;
    var g: usize = 0;
    var b: usize = 0;
    var count: usize = 0;

    var i: usize = 0;
    while (i + 2 < pixels.len) : (i += 3) {
        b += pixels[i];
        g += pixels[i + 1];
        r += pixels[i + 2];
        count += 1;
    }
    if (count > 0) {
        var r_out: f64 = @as(f64, @floatFromInt(r)) / @as(f64, @floatFromInt(count));
        var g_out: f64 = @as(f64, @floatFromInt(g)) / @as(f64, @floatFromInt(count));
        var b_out: f64 = @as(f64, @floatFromInt(b)) / @as(f64, @floatFromInt(count));

        const max_c = @max(r_out, @max(g_out, b_out));
        if (max_c < 160.0 and max_c > 0.0) {
            const scale = 160.0 / max_c;
            r_out *= scale;
            g_out *= scale;
            b_out *= scale;
        } else if (max_c == 0) {
            r_out = 160;
            g_out = 160;
            b_out = 160;
        }

        state.extracted_r = @intFromFloat(if (r_out > 255.0) 255.0 else r_out);
        state.extracted_g = @intFromFloat(if (g_out > 255.0) 255.0 else g_out);
        state.extracted_b = @intFromFloat(if (b_out > 255.0) 255.0 else b_out);
    }
}
