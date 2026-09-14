with open("src/graphics/render.zig", "r") as f:
    text = f.read()

# I will find the block: @import("../platform/native.zig").wallify_load_texture(target_tex, text_buffer[0..].ptr, w_px, h_px);
# And insert a vertical flip right before it!

flip_block = """
        // Vertical flip for Metal Texture Top-Left Origin
        const row_len = w_px;
        var y_idx: usize = 0;
        while (y_idx < h_px / 2) : (y_idx += 1) {
            const opp_y = h_px - 1 - y_idx;
            for (0..row_len) |x_idx| {
                const tmp = text_buffer[y_idx * row_len + x_idx];
                text_buffer[y_idx * row_len + x_idx] = text_buffer[opp_y * row_len + x_idx];
                text_buffer[opp_y * row_len + x_idx] = tmp;
            }
        }
"""

text = text.replace('@import("../platform/native.zig").wallify_load_texture(target_tex, text_buffer[0..].ptr, w_px, h_px);', flip_block + '\n        @import("../platform/native.zig").wallify_load_texture(target_tex, text_buffer[0..].ptr, w_px, h_px);')

with open("src/graphics/render.zig", "w") as f:
    f.write(text)

