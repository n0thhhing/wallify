with open("src/graphics/render.zig", "r") as f:
    text = f.read()

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
"""

if "TextCacheItem =" not in text:
    text = text.replace("var shared_frame_id: u64 = 0;", "var shared_frame_id: u64 = 0;\n" + cache_struct)

new_draw_text = """
pub fn drawText(engine: *PixelEngine, text_str: []const u8, x: f64, y: f64, width: f64, size: f64, bold: bool, right: bool, color: [3]u8, commands: *var, cmd_count: *usize) void {
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
        // Evict or use new
        const idx = @as(usize, @intCast((next_tex_id - 4) % 12));
        target_tex = next_tex_id;
        next_tex_id += 1;
        if (next_tex_id > 15) next_tex_id = 4;
        
        const w_px = @as(usize, @intFromFloat(try std.math.ceil(width * state.render_scale)));
        const h_px = @as(usize, @intFromFloat(try std.math.ceil(size * state.render_scale * 2.0)));
        if (w_px * h_px > text_buffer.len) return;

        @memset(text_buffer[0..w_px * h_px], 0);
        text_renderer.widget_text(text_buffer[0..].ptr, w_px, h_px, text_str.ptr, text_str.len, 0, 0, width * state.render_scale, size * state.render_scale, @intFromBool(bold), @intFromBool(right), color[0], color[1], color[2]);
        
        for (0..w_px * h_px) |i| {
            // Un-swap R/B if CoreText exports RGBA, or maybe CoreText exports BGRA?
            // Actually, macOS standard CoreGraphics writes ARGB/BGRA natively depending on endianness.
            // Let's just swap R&B in Zig to be perfectly safe, identical to our native.m loop:
            const p = text_buffer[i];
            const a = (p >> 24) & 0xFF;
            const r = (p >> 16) & 0xFF;
            const g = (p >> 8) & 0xFF;
            const b = p & 0xFF;
            text_buffer[i] = (a << 24) | (b << 16) | (g << 8) | r;
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
"""

with open("src/graphics/render.zig", "w") as f:
    text = text.replace("pub fn drawText(engine: *PixelEngine, text: []const u8, x: f64, y: f64, width: f64, size: f64, bold: bool, right: bool, color: [3]u8) void {", new_draw_text)
    f.write(text)

