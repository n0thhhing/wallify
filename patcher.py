import re

with open("src/graphics/render.zig", "r") as f:
    text = f.read()

# 1. Insert TextCache structs
cache_struct = """
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

pub fn drawText(engine: *PixelEngine, text_str: []const u8, x: f64, y: f64, width: f64, size: f64, bold: bool, right: bool, color: [3]u8, commands: []@import("../platform/native.zig").DrawCommand, cmd_count: *usize) void {
    _ = engine; // We don't use CPU engine anymore!
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
        const h_px = @as(usize, @intFromFloat(@ceil(size * state.render_scale * 2.0)));
        if (w_px * h_px > text_buffer.len) return;

        @memset(text_buffer[0..w_px * h_px], 0);
        text_renderer.widget_text(text_buffer[0..].ptr, w_px, h_px, text_str.ptr, text_str.len, 0, 0, width * state.render_scale, size * state.render_scale, @intFromBool(bold), @intFromBool(right), color[0], color[1], color[2]);
        
        for (0..w_px * h_px) |i| {
            const p = text_buffer[i];
            const a = (p >> 24) & 0xFF;
            const r = (p >> 16) & 0xFF;
            const g = (p >> 8) & 0xFF;
            const b = p & 0xFF;
            text_buffer[i] = (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r); // swap R and B
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
}

fn drawMarqueeText(engine: *PixelEngine, text_str: []const u8, x: f64, y: f64, viewport_width: f64, offset: f64, color: [3]u8, commands: []@import("../platform/native.zig").DrawCommand, cmd_count: *usize) void {
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
        const h_px = @as(usize, @intFromFloat(@ceil(size * state.render_scale * 2.0)));
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

# I need to wipe out the old python injection I did which added drawText and the duplicated struct
# Actually I'll do `git restore src/graphics/render.zig` in the bash script to ensure a clean slate,
# then we will manually build my regexes based on the pristine file!

