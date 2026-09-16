const std = @import("std");
const native = @import("../platform/native.zig");
const raster = @import("text.zig");
const gpu = @import("canvas.zig");
const density = @import("../state.zig").render_scale;
const capacity = 32;
const first_texture = @intFromEnum(gpu.Texture.text_start);
const Entry = struct { hash: u64 = 0, valid: bool = false, width: f64 = 0, height: f64 = 0, stamp: u64 = 0 };
var entries = [_]Entry{.{}} ** capacity;
var tick: u64 = 0;
const max_width = 4096;
const max_height = 128;
var scratch: [max_width * max_height]u32 = undefined;

fn get(text: []const u8, size: f64, bold: bool) ?usize {
    var hash = std.hash.Wyhash.init(0);
    hash.update(text);
    hash.update(std.mem.asBytes(&size));
    hash.update(&.{@intFromBool(bold)});
    const key = hash.final();
    tick += 1;
    var oldest: usize = 0;
    for (&entries, 0..) |*entry, i| {
        if (entry.valid and entry.hash == key) {
            entry.stamp = tick;
            return i;
        }
        if (entry.stamp < entries[oldest].stamp) oldest = i;
    }
    const raster_width = @min(max_width, @ceil(raster.widget_text_width(text.ptr, text.len, size * density, @intFromBool(bold))) + 8);
    const height = @min(max_height, @ceil(size * density * 1.5));
    const w: usize = @intFromFloat(raster_width);
    const h: usize = @intFromFloat(height);
    if (w == 0 or h == 0) return null;
    @memset(scratch[0 .. w * h], 0);
    raster.widget_text(&scratch, w, h, text.ptr, text.len, 0, 0, raster_width, size * density, @intFromBool(bold), 0, 255, 255, 255);
    native.wallify_load_texture(@intCast(first_texture + oldest), &scratch, w, h);
    entries[oldest] = .{ .valid = true, .hash = key, .width = raster_width / density, .height = height / density, .stamp = tick };
    return oldest;
}

pub fn width(text: []const u8, size: f64, bold: bool) f64 {
    const idx = get(text, size, bold) orelse return 0;
    return @max(0, entries[idx].width - 8.0 / density);
}

// Font masks are cached at a stable size; layout morphs scale quads, not glyph bitmaps.
pub fn draw(canvas: *gpu.Canvas, text: []const u8, x: f64, y: f64, viewport: f64, font: f64, scale: f64, bold: bool, color: gpu.Color, offset: f64, right: bool, ellipsis: bool) void {
    if (text.len == 0 or viewport <= 0) return;
    const idx = get(text, font, bold) orelse return;
    const entry = entries[idx];
    const full = entry.width * scale;
    const pad = (8.0 / density) * scale;
    const glyph_w = @max(0, full - pad);
    const crop = @max(0, @min(offset, full - viewport));
    const clipped = ellipsis and full - 4 * scale > viewport;
    const dots_width: f64 = if (clipped) width("…", font, bold) * scale else 0;
    const shown = @min(@max(0, viewport - dots_width), full - crop);
    const origin = if (right) x + @max(0, viewport - glyph_w) else x;
    const c = canvas.add(native.gpu.WALLIFY_TEXTURE, @intCast(first_texture + idx), .{ .x = origin, .y = y, .w = shown, .h = entry.height * scale }, color);
    c.sx = @floatCast(crop / full);
    c.sw = @floatCast(shown / full);
    if (clipped) draw(canvas, "…", x + viewport - dots_width, y, dots_width + 4, font, scale, bold, color, 0, false, false);
}
