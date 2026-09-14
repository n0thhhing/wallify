import re

with open("src/graphics/render.zig", "r") as f:
    text = f.read()

# Add loadBmpToTexture at the end of the file
album_func = """
fn loadBmpToTexture(texture_id: c_int, bmp_data: []const u8) void {
    if (bmp_data.len < 54) return;
    const width = std.mem.readInt(i32, bmp_data[18..22], .little);
    const height_signed = std.mem.readInt(i32, bmp_data[22..26], .little);
    const bpp = std.mem.readInt(u16, bmp_data[28..30], .little);
    const offset_val = std.mem.readInt(u32, bmp_data[10..14], .little);

    if (bpp != 24 or width <= 0 or height_signed == 0) return;
    const w = @as(usize, @intCast(width));
    const h = @as(usize, @intCast(if (height_signed < 0) -height_signed else height_signed));
    const is_top_down = (height_signed < 0);
    const row_stride = (w * 3 + 3) & ~@as(usize, 3);
    
    if (offset_val > bmp_data.len or h > (bmp_data.len - offset_val) / row_stride) return;
    
    var buf = std.heap.page_allocator.alloc(u32, w * h) catch return;
    defer std.heap.page_allocator.free(buf);
    
    const r_pcnt = 6.0 / 150.0;
    const r_px = @as(f64, @floatFromInt(w)) * r_pcnt;
    const r_sq = r_px * r_px;
    
    for (0..h) |y| {
        const src_y = if (is_top_down) y else h - 1 - y;
        const src_row = bmp_data[offset_val + src_y * row_stride ..];
        for (0..w) |x| {
            var alpha: u32 = 255;
            
            // Corner radius check
            var dx: f64 = 0;
            var dy: f64 = 0;
            if (@as(f64, @floatFromInt(x)) < r_px) dx = r_px - @as(f64, @floatFromInt(x));
            if (@as(f64, @floatFromInt(x)) > @as(f64, @floatFromInt(w)) - r_px) dx = @as(f64, @floatFromInt(x)) - (@as(f64, @floatFromInt(w)) - r_px);
            if (@as(f64, @floatFromInt(y)) < r_px) dy = r_px - @as(f64, @floatFromInt(y));
            if (@as(f64, @floatFromInt(y)) > @as(f64, @floatFromInt(h)) - r_px) dy = @as(f64, @floatFromInt(y)) - (@as(f64, @floatFromInt(h)) - r_px);
            
            if (dx * dx + dy * dy > r_sq) alpha = 0;
            
            const b = src_row[x * 3];
            const g = src_row[x * 3 + 1];
            const r = src_row[x * 3 + 2];
            
            // BGRA (Metal expects BGRA8Unorm, so native little-endian memory layout must be B,G,R,A)
            // On MacOS arm64 (little endian), a u32 is stored A-R-G-B in higher bits, so:
            // byte0=B, byte1=G, byte2=R, byte3=A
            // Which means (A << 24) | (R << 16) | (G << 8) | B
            const pixel = (alpha << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
            buf[y * w + x] = pixel;
        }
    }
    
    @import("../platform/native.zig").wallify_load_texture(texture_id, buf.ptr, w, h);
}
"""
text = text + "\n" + album_func

# Replace extractColor inside
extract_block_old = """        if (state.cached_art.len > 0) {
            if (!std.mem.eql(u8, state.cached_art, buf)) {
                if (state.previous_art.len > 0) std.heap.page_allocator.free(state.previous_art);
                state.previous_art = state.cached_art;
                state.cached_art = std.heap.page_allocator.dupe(u8, buf) catch return;
                state.global_anim_art_t = 0.0;
                window.widget_render_wake(); // wake to animate
            }
        } else {
            state.cached_art = std.heap.page_allocator.dupe(u8, buf) catch return;
            window.widget_render_wake();
        }"""
        
extract_block_new = """        if (state.cached_art.len > 0) {
            if (!std.mem.eql(u8, state.cached_art, buf)) {
                if (state.previous_art.len > 0) std.heap.page_allocator.free(state.previous_art);
                state.previous_art = state.cached_art;
                state.cached_art = std.heap.page_allocator.dupe(u8, buf) catch return;
                
                @import("../platform/native.zig").wallify_swap_textures(1, 2);
                loadBmpToTexture(1, state.cached_art);
                
                state.global_anim_art_t = 0.0;
                window.widget_render_wake(); // wake to animate
            }
        } else {
            state.cached_art = std.heap.page_allocator.dupe(u8, buf) catch return;
            loadBmpToTexture(1, state.cached_art);
            window.widget_render_wake();
        }"""

text = text.replace(extract_block_old, extract_block_new)

# Modify drawUIFrame to map DrawCommands instead of blitBMP
drawUIFrame_old = """    if (state.cached_art.len > 0) {
        if (state.global_anim_art_t < 1.0) {
            if (state.previous_art.len > 0) {
                engine.blitBMP(state.previous_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
                var alpha: u8 = @intFromFloat(ease * 255);
                if (ease >= 1.0) alpha = 255;
                if (alpha > 0 and state.cached_art.len > 0) {
                    engine.blitBMPAlpha(state.cached_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius, alpha);
                }
            } else {
                engine.blitBMP(state.cached_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
            }
        } else {
            if (state.previous_art.len > 0) {
                std.heap.page_allocator.free(state.previous_art);
                state.previous_art = &.{};
            }
            engine.blitBMP(state.cached_art, art_offset_x, art_offset_y, art_size_draw, art_corner_radius);
        }
    }"""
    
drawUIFrame_new = """    if (state.cached_art.len > 0) {
        if (state.global_anim_art_t < 1.0) {
            if (state.previous_art.len > 0) {
                const alpha: f32 = @floatCast(ease);
                
                commands[cmd_count.*] = .{
                    .texture_id = 2,
                    .dx = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_x)) * scale)),
                    .dy = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_y)) * scale)),
                    .dw = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                    .dh = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                    .sx = 0, .sy = 0, .sw = 1, .sh = 1,
                    .alpha = 1.0,
                };
                cmd_count.* += 1;
                
                if (alpha > 0.0) {
                    commands[cmd_count.*] = .{
                        .texture_id = 1,
                        .dx = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_x)) * scale)),
                        .dy = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_y)) * scale)),
                        .dw = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                        .dh = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                        .sx = 0, .sy = 0, .sw = 1, .sh = 1,
                        .alpha = alpha,
                    };
                    cmd_count.* += 1;
                }
            } else {
                commands[cmd_count.*] = .{
                    .texture_id = 1,
                    .dx = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_x)) * scale)),
                    .dy = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_y)) * scale)),
                    .dw = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                    .dh = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                    .sx = 0, .sy = 0, .sw = 1, .sh = 1,
                    .alpha = 1.0,
                };
                cmd_count.* += 1;
            }
        } else {
            if (state.previous_art.len > 0) {
                std.heap.page_allocator.free(state.previous_art);
                state.previous_art = &.{};
            }
            commands[cmd_count.*] = .{
                .texture_id = 1,
                .dx = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_x)) * scale)),
                .dy = @as(f32, @floatCast(@as(f64, @floatFromInt(art_offset_y)) * scale)),
                .dw = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                .dh = @as(f32, @floatCast(@as(f64, @floatFromInt(art_size_draw)) * scale)),
                .sx = 0, .sy = 0, .sw = 1, .sh = 1,
                .alpha = 1.0,
            };
            cmd_count.* += 1;
        }
    }"""
    
text = text.replace(drawUIFrame_old, drawUIFrame_new)

with open("src/graphics/render.zig", "w") as f:
    f.write(text)
