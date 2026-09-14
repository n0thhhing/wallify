import re
with open("src/graphics/render.zig", "r") as f:
    text = f.read()

# 1. ADD Text Cache Variables
text = text.replace("var shared_frame_id: u64 = 0;", """var shared_frame_id: u64 = 0;

const TextCacheItem = struct {
    hash: u64 = 0,
    w: usize = 0,
    h: usize = 0,
    tex_id: c_int = 0,
};
var text_cache: [12]TextCacheItem = undefined;
var next_tex_id: c_int = 4;
var text_buffer: [1000 * 100]u32 = undefined; // scratch buffer

fn hashText(text: []const u8, size: f64, bold: bool, color: [3]u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(text);
    const sz_bytes = std.mem.asBytes(&size);
    hasher.update(sz_bytes);
    hasher.update(&[_]u8{@intFromBool(bold), color[0], color[1], color[2]});
    return hasher.final();
}
""")

# 2. REPLACE drawText EXACTLY
drawText_pattern = re.compile(r'pub fn drawText[\s\S]*?widget_text[^\n]*\n\}')
drawText_new = """pub fn drawText(engine: *PixelEngine, text_str: []const u8, x: f64, y: f64, width: f64, size: f64, bold: bool, right: bool, color: [3]u8, commands: []@import("../platform/native.zig").DrawCommand, cmd_count: *usize) void {
    _ = engine;
    if (text_str.len == 0 or width <= 0 or cmd_count.* >= 16) return;
    const h = hashText(text_str, size, bold, color);
    var target_idx: ?usize = null;
    var target_tex: c_int = -1;
    var cached_w: usize = 0;
    var cached_h: usize = 0;
    for (0..12) |i| {
        if (text_cache[i].hash == h) {
            target_idx = i;
            target_tex = text_cache[i].tex_id;
            cached_w = text_cache[i].w;
            cached_h = text_cache[i].h;
            break;
        }
    }
    if (target_idx == null) {
        const idx = @as(usize, @intCast((next_tex_id - 4) % 12));
        target_tex = next_tex_id;
        next_tex_id += 1;
        if (next_tex_id > 15) next_tex_id = 4;
        
        const w_px = @as(usize, @intFromFloat(@ceil(width * state.render_scale)));
        const h_px = @as(usize, @intFromFloat(@ceil(size * state.render_scale * 2.8)));
        if (w_px * h_px > text_buffer.len) return;

        @memset(text_buffer[0..w_px * h_px], 0);
        text_renderer.widget_text(text_buffer[0..].ptr, w_px, h_px, text_str.ptr, text_str.len, 0, 0, width * state.render_scale, size * state.render_scale, @intFromBool(bold), @intFromBool(right), color[0], color[1], color[2]);
        
        for (0..w_px * h_px) |i| {
            const p = text_buffer[i];
            const a = (p >> 24) & 0xFF;
            const r = (p >> 16) & 0xFF;
            const g = (p >> 8) & 0xFF;
            const b = p & 0xFF;
            text_buffer[i] = (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
        }
        @import("../platform/native.zig").wallify_load_texture(target_tex, text_buffer[0..].ptr, w_px, h_px);
        
        text_cache[idx] = .{ .hash = h, .w = w_px, .h = h_px, .tex_id = target_tex };
        cached_w = w_px;
        cached_h = h_px;
    }

    commands[cmd_count.*] = .{
        .texture_id = target_tex,
        .dx = @as(f32, @floatFromInt(x)),
        .dy = @as(f32, @floatFromInt(y)),
        .dw = @as(f32, @floatFromInt(cached_w)) / @as(f32, @floatFromInt(state.render_scale)),
        .dh = @as(f32, @floatFromInt(cached_h)) / @as(f32, @floatFromInt(state.render_scale)),
        .sx = 0, .sy = 0, .sw = 1, .sh = 1,
        .alpha = 1.0,
    };
    cmd_count.* += 1;
}"""
text = drawText_pattern.sub(drawText_new, text)


# 3. REPLACE drawMarqueeText EXACTLY
marquee_pattern = re.compile(r'fn drawMarqueeText[\s\S]*?\}\n')
marquee_new = """fn drawMarqueeText(engine: *PixelEngine, text_str: []const u8, x: f64, y: f64, viewport_width: f64, offset: f64, color: [3]u8, commands: []@import("../platform/native.zig").DrawCommand, cmd_count: *usize) void {
    _ = engine;
    if (text_str.len == 0 or viewport_width <= 0 or cmd_count.* >= 16) return;
    const size = 15;
    const h = hashText(text_str, size, true, color);
    var target_idx: ?usize = null;
    var target_tex: c_int = -1;
    var cached_w: usize = 0;
    var cached_h: usize = 0;
    for (0..12) |i| {
        if (text_cache[i].hash == h) {
            target_idx = i;
            target_tex = text_cache[i].tex_id;
            cached_w = text_cache[i].w;
            cached_h = text_cache[i].h;
            break;
        }
    }
    if (target_idx == null) {
        const full_width = text_renderer.widget_text_width(text_str.ptr, text_str.len, size * state.render_scale, 1) / @as(f64, @floatFromInt(state.render_scale));
        const alloc_w = full_width + 10;
        const idx = @as(usize, @intCast((next_tex_id - 4) % 12));
        target_tex = next_tex_id;
        next_tex_id += 1;
        if (next_tex_id > 15) next_tex_id = 4;
        
        const w_px = @as(usize, @intFromFloat(@ceil(alloc_w * state.render_scale)));
        const h_px = @as(usize, @intFromFloat(@ceil(size * state.render_scale * 2.8)));
        if (w_px * h_px > text_buffer.len) return;
        @memset(text_buffer[0..w_px * h_px], 0);
        text_renderer.widget_text(text_buffer[0..].ptr, w_px, h_px, text_str.ptr, text_str.len, 0, 0, alloc_w * state.render_scale, size * state.render_scale, 1, 0, color[0], color[1], color[2]);
        for (0..w_px * h_px) |i| {
            const p = text_buffer[i];
            const a = (p >> 24) & 0xFF;
            const r = (p >> 16) & 0xFF;
            const g = (p >> 8) & 0xFF;
            const b = p & 0xFF;
            text_buffer[i] = (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
        }
        @import("../platform/native.zig").wallify_load_texture(target_tex, text_buffer[0..].ptr, w_px, h_px);
        text_cache[idx] = .{ .hash = h, .w = w_px, .h = h_px, .tex_id = target_tex };
        cached_w = w_px;
        cached_h = h_px;
    }
    
    const visible_w_px = @min(cached_w, @as(usize, @intFromFloat(viewport_width * state.render_scale)));
    const offset_px = @as(usize, @intFromFloat(offset * state.render_scale));
    
    commands[cmd_count.*] = .{
        .texture_id = target_tex,
        .dx = @as(f32, @floatFromInt(x)),
        .dy = @as(f32, @floatFromInt(y)),
        .dw = @as(f32, @floatFromInt(visible_w_px)) / @as(f32, @floatFromInt(state.render_scale)),
        .dh = @as(f32, @floatFromInt(cached_h)) / @as(f32, @floatFromInt(state.render_scale)),
        .sx = @as(f32, @floatFromInt(offset_px)) / @as(f32, @floatFromInt(cached_w)),
        .sy = 0,
        .sw = @as(f32, @floatFromInt(visible_w_px)) / @as(f32, @floatFromInt(cached_w)),
        .sh = 1,
        .alpha = 1.0,
    };
    cmd_count.* += 1;
}
"""
text = marquee_pattern.sub(marquee_new, text)

# 4. FIX Signatures and calls
text = text.replace("fn drawTextOverlays(engine: *PixelEngine, debug_x: isize, debug_y: isize, displayed_elapsed: f64) void {", "fn drawTextOverlays(engine: *PixelEngine, debug_x: isize, debug_y: isize, displayed_elapsed: f64, commands: []@import(\"../platform/native.zig\").DrawCommand, cmd_count: *usize) void {")

text = text.replace("drawText(engine, \"Open Spotify\", 210, 85, state.layout.bar_w, 17, true, false, .{ 240, 235, 225 });", "drawText(engine, \"Open Spotify\", 210, 85, state.layout.bar_w, 17, true, false, .{ 240, 235, 225 }, commands, cmd_count);")
text = text.replace("drawText(engine, \"Click to launch\", 210, 112, state.layout.bar_w, 13, false, false, .{ 159, 153, 145 });", "drawText(engine, \"Click to launch\", 210, 112, state.layout.bar_w, 13, false, false, .{ 159, 153, 145 }, commands, cmd_count);")

text = text.replace("drawText(engine, artist, 24, @floatFromInt(mini_card_y + 137), 132, 11, false, false, secondary);", "drawText(engine, artist, 24, @floatFromInt(mini_card_y + 137), 132, 11, false, false, secondary, commands, cmd_count);")
text = text.replace("drawMarqueeText(engine, title, text_x, title_y, text_width, offset, primary);", "drawMarqueeText(engine, title, text_x, title_y, text_width, offset, primary, commands, cmd_count);")

text = text.replace("drawText(engine, title, text_x, title_y, text_width, title_size, true, false, primary);", "drawText(engine, title, text_x, title_y, text_width, title_size, true, false, primary, commands, cmd_count);")
text = text.replace("drawText(engine, if (artist.len > 0) artist else \"Play something to get started\", text_x, artist_y, text_width, artist_size, false, false, secondary);", "drawText(engine, if (artist.len > 0) artist else \"Play something to get started\", text_x, artist_y, text_width, artist_size, false, false, secondary, commands, cmd_count);")

text = text.replace("drawText(engine, elapsed_text, text_x, state.layout.bar_y + 13, 100, 12, false, false, secondary);", "drawText(engine, elapsed_text, text_x, state.layout.bar_y + 13, 100, 12, false, false, secondary, commands, cmd_count);")
text = text.replace("drawText(engine, duration_text, text_x, state.layout.bar_y + 13, state.layout.bar_w, 12, false, true, secondary);", "drawText(engine, duration_text, text_x, state.layout.bar_y + 13, state.layout.bar_w, 12, false, true, secondary, commands, cmd_count);")

text = text.replace("""fn publishFrame(engine: *PixelEngine, wide: bool) void {
    _ = wide;
    var commands: [16]@import("../platform/native.zig").DrawCommand = undefined;
    var cmd_count: usize = 0;""", """fn publishFrame(engine: *PixelEngine, wide: bool, commands: []@import("../platform/native.zig").DrawCommand, cmd_count: *usize) void {
    _ = wide;""")

text = text.replace("""        if (state.setting_idle_style != .spotify and state.setting_animations) {
            const fps: f64 = switch (state.setting_idle_style) {
                .banana_cat => 24,
                .pixel_cat => 8,
                else => 24,
            };
            const time = @max(0.0, state.animation_time - state.anim_idle_start);
            const frame: usize = @intFromFloat(time * fps);
            switch (state.setting_idle_style) {
                .banana_cat => @import("pets/banana.zig").draw(engine, x, 35, w, frame, &commands, &cmd_count),
                .pixel_cat => @import("pets/idle_cat.zig").draw(engine, x, 35, w, state.cat_time, false, 0, false, &commands, &cmd_count),
                else => {},
            }
        }
    }
    @import("../platform/native.zig").wallify_present(engine.pixels.ptr, engine.width, engine.height, &commands, cmd_count);""",
"""        if (state.setting_idle_style != .spotify and state.setting_animations) {
            const fps: f64 = switch (state.setting_idle_style) {
                .banana_cat => 24,
                .pixel_cat => 8,
                else => 24,
            };
            const time = @max(0.0, state.animation_time - state.anim_idle_start);
            const frame: usize = @intFromFloat(time * fps);
            switch (state.setting_idle_style) {
                .banana_cat => @import("pets/banana.zig").draw(engine, x, 35, w, frame, commands, cmd_count),
                .pixel_cat => @import("pets/idle_cat.zig").draw(engine, x, 35, w, state.cat_time, false, 0, false, commands, cmd_count),
                else => {},
            }
        }
    }
    @import("../platform/native.zig").wallify_present(engine.pixels.ptr, engine.width, engine.height, commands.ptr, cmd_count.*);""")


text = text.replace("""pub fn drawUIFrame() void {
    window.widget_render_lock();
    defer window.widget_render_unlock();""", """pub fn drawUIFrame() void {
    window.widget_render_lock();
    defer window.widget_render_unlock();
    var commands_arr: [32]@import("../platform/native.zig").DrawCommand = undefined;
    var commands: []@import("../platform/native.zig").DrawCommand = &commands_arr;
    var cmd_count: usize = 0;""")

text = text.replace("return publishFrame(&engine, wide);", "return publishFrame(&engine, wide, commands, &cmd_count);")
text = text.replace("publishFrame(&engine, wide);", "publishFrame(&engine, wide, commands, &cmd_count);")

text = text.replace("drawTextOverlays(&engine, if (wide) 650 else 24, if (wide) 20 else 220, displayed_elapsed);", 
"drawTextOverlays(&engine, if (wide) 650 else 24, if (wide) 20 else 220, displayed_elapsed, commands, &cmd_count);")

with open("src/graphics/render.zig", "w") as f:
    f.write(text)
