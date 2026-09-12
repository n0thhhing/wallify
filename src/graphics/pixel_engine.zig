const std = @import("std");

pub const PixelEngine = struct {
    scale: isize = 1,
    width: usize,
    height: usize,
    pixels: []u32,

    pub fn init(allocator: std.mem.Allocator, w: usize, h: usize) !PixelEngine {
        const pixels = try allocator.alloc(u32, w * h);
        @memset(pixels, 0);
        return PixelEngine{ .width = w, .height = h, .pixels = pixels };
    }

    pub fn deinit(self: *PixelEngine, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }

    pub inline fn blendPixel(self: *PixelEngine, x: isize, y: isize, r: u8, g: u8, b: u8, a: u8) void {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height or a == 0) return;
        const idx = @as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x));
        const rgb = @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16);

        if (a == 255) {
            self.pixels[idx] = rgb | 0xFF000000;
            return;
        }

        const curr = self.pixels[idx];
        const ca = (curr >> 24) & 0xFF;

        if (ca == 0) {
            self.pixels[idx] = rgb | (@as(u32, a) << 24);
            return;
        }

        const cr = curr & 0xFF;
        const cg = (curr >> 8) & 0xFF;
        const cb = (curr >> 16) & 0xFF;

        const alpha = @as(u32, a);
        const inv_alpha = 255 - alpha;

        const nr = (r * alpha + cr * inv_alpha + 127) / 255;
        const ng = (g * alpha + cg * inv_alpha + 127) / 255;
        const nb = (b * alpha + cb * inv_alpha + 127) / 255;
        const na = @max(ca, alpha);

        self.pixels[idx] = nr | (ng << 8) | (nb << 16) | (na << 24);
    }

    pub fn fillGlowRoundedRect(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, radius_logical: isize, base_r: u8, base_g: u8, base_b: u8, a: u8, glow_r: u8, glow_g: u8, glow_b: u8) void {
        const start_x = start_x_logical * self.scale;
        const start_y = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        const radius = radius_logical * self.scale;
        const rad = @as(f64, @floatFromInt(radius));
        const rad_sq = rad * rad;
        const wi = @as(f64, @floatFromInt(w));
        const hi = @as(f64, @floatFromInt(h));

        const glow_cx = 100.0 * @as(f64, @floatFromInt(self.scale));
        const glow_cy = 100.0 * @as(f64, @floatFromInt(self.scale));
        const glow_extent = 350.0 * @as(f64, @floatFromInt(self.scale));

        for (0..@as(usize, @intCast(h))) |y_u| {
            const yt = @as(f64, @floatFromInt(y_u)) + 0.5;
            const py = start_y + @as(isize, @intCast(y_u));
            if (py < 0 or py >= self.height) continue;

            const is_corner_y = (radius > 0) and (yt < rad or yt > hi - rad);

            for (0..@as(usize, @intCast(w))) |x_u| {
                const px = start_x + @as(isize, @intCast(x_u));
                if (px < 0 or px >= self.width) continue;

                const xt = @as(f64, @floatFromInt(x_u)) + 0.5;
                var alpha: f64 = 1.0;

                if (is_corner_y and (xt < rad or xt > wi - rad)) {
                    var cx: f64 = 0.0;
                    var cy: f64 = 0.0;
                    if (xt < rad and yt < rad) {
                        cx = rad - xt;
                        cy = rad - yt;
                    } else if (xt > wi - rad and yt < rad) {
                        cx = xt - (wi - rad);
                        cy = rad - yt;
                    } else if (xt < rad and yt > hi - rad) {
                        cx = rad - xt;
                        cy = yt - (hi - rad);
                    } else {
                        cx = xt - (wi - rad);
                        cy = yt - (hi - rad);
                    }
                    const d_sq = cx * cx + cy * cy;
                    if (d_sq > rad_sq) {
                        const d = @sqrt(d_sq);
                        if (d > rad + 1.0) alpha = 0.0 else alpha = 1.0 - (d - rad);
                    }
                }

                if (alpha > 0.0) {
                    const final_a = @as(u8, @intFromFloat(@as(f64, @floatFromInt(a)) * alpha));
                    const dist_glow = @sqrt((xt - glow_cx) * (xt - glow_cx) + (yt - glow_cy) * (yt - glow_cy));
                    var mix: f64 = 0.0;
                    if (dist_glow < glow_extent) {
                        mix = (glow_extent - dist_glow) / glow_extent;
                        mix = mix * mix * mix * 0.65;
                    }

                    const fr = @as(f64, @floatFromInt(base_r)) + (@as(f64, @floatFromInt(glow_r)) - @as(f64, @floatFromInt(base_r))) * mix;
                    const fg_val = @as(f64, @floatFromInt(base_g)) + (@as(f64, @floatFromInt(glow_g)) - @as(f64, @floatFromInt(base_g))) * mix;
                    const fb = @as(f64, @floatFromInt(base_b)) + (@as(f64, @floatFromInt(glow_b)) - @as(f64, @floatFromInt(base_b))) * mix;

                    const idx = @as(usize, @intCast(py)) * self.width + @as(usize, @intCast(px));
                    if (final_a == 255) {
                        self.pixels[idx] = @as(u32, @intFromFloat(fr)) | (@as(u32, @intFromFloat(fg_val)) << 8) | (@as(u32, @intFromFloat(fb)) << 16) | 0xFF000000;
                    } else {
                        self.blendPixel(px, py, @as(u8, @intFromFloat(fr)), @as(u8, @intFromFloat(fg_val)), @as(u8, @intFromFloat(fb)), final_a);
                    }
                }
            }
        }
    }

    pub fn fillRoundedRect(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, radius_logical: isize, r: u8, g: u8, b: u8, a: u8) void {
        const start_x = start_x_logical * self.scale;
        const start_y = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        const radius = radius_logical * self.scale;
        if (w <= 0 or h <= 0 or a == 0) return;
        const rad = @as(f64, @floatFromInt(radius));
        const rad_sq = rad * rad;
        const wi = @as(f64, @floatFromInt(w));
        const hi = @as(f64, @floatFromInt(h));
        const color_val = @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16) | (@as(u32, a) << 24);

        for (0..@as(usize, @intCast(h))) |y_u| {
            const py = start_y + @as(isize, @intCast(y_u));
            if (py < 0 or py >= self.height) continue;
            const yt = @as(f64, @floatFromInt(y_u)) + 0.5;
            const is_corner_y = (radius > 0) and (yt < rad or yt > hi - rad);

            for (0..@as(usize, @intCast(w))) |x_u| {
                const px = start_x + @as(isize, @intCast(x_u));
                if (px < 0 or px >= self.width) continue;

                const xt = @as(f64, @floatFromInt(x_u)) + 0.5;
                var alpha: f64 = 1.0;

                if (is_corner_y and (xt < rad or xt > wi - rad)) {
                    var cx: f64 = 0.0;
                    var cy: f64 = 0.0;
                    if (xt < rad and yt < rad) {
                        cx = rad - xt;
                        cy = rad - yt;
                    } else if (xt > wi - rad and yt < rad) {
                        cx = xt - (wi - rad);
                        cy = rad - yt;
                    } else if (xt < rad and yt > hi - rad) {
                        cx = rad - xt;
                        cy = yt - (hi - rad);
                    } else {
                        cx = xt - (wi - rad);
                        cy = yt - (hi - rad);
                    }
                    const d_sq = cx * cx + cy * cy;
                    if (d_sq > rad_sq) {
                        const d = @sqrt(d_sq);
                        if (d > rad + 1.0) alpha = 0.0 else alpha = 1.0 - (d - rad);
                    }
                }

                if (alpha > 0.0) {
                    if (alpha == 1.0 and a == 255) {
                        const idx = @as(usize, @intCast(py)) * self.width + @as(usize, @intCast(px));
                        self.pixels[idx] = color_val;
                    } else {
                        const final_a = @as(u8, @intFromFloat(@as(f64, @floatFromInt(a)) * alpha));
                        self.blendPixel(px, py, r, g, b, final_a);
                    }
                }
            }
        }
    }

    /// A bottom-to-top translucent wash that preserves the alpha silhouette
    /// already present in the canvas. It is useful for text over artwork.
    pub fn bottomScrim(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, top_alpha: u8, bottom_alpha: u8) void {
        const start_x = start_x_logical * self.scale;
        const start_y = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        if (w <= 0 or h <= 0) return;
        for (0..@as(usize, @intCast(h))) |y_u| {
            const py = start_y + @as(isize, @intCast(y_u));
            if (py < 0 or py >= self.height) continue;
            const progress = (@as(f64, @floatFromInt(y_u)) + 0.5) / @as(f64, @floatFromInt(h));
            const alpha: u8 = @intFromFloat(@as(f64, @floatFromInt(top_alpha)) + (@as(f64, @floatFromInt(bottom_alpha)) - @as(f64, @floatFromInt(top_alpha))) * progress);
            for (0..@as(usize, @intCast(w))) |x_u| {
                const px = start_x + @as(isize, @intCast(x_u));
                if (px < 0 or px >= self.width) continue;
                const index = @as(usize, @intCast(py)) * self.width + @as(usize, @intCast(px));
                if ((self.pixels[index] >> 24) != 0) self.blendPixel(px, py, 0, 0, 0, alpha);
            }
        }
    }

    /// Final alpha mask for a widget. This also contains effects that are
    /// intentionally drawn larger than the artwork, such as its glow.
    pub fn clipOutsideRoundedRect(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, radius_logical: isize) void {
        const x0 = start_x_logical * self.scale;
        const y0 = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        const radius = radius_logical * self.scale;
        if (w <= 0 or h <= 0) return;
        const wf: f64 = @floatFromInt(w);
        const hf: f64 = @floatFromInt(h);
        const rf: f64 = @floatFromInt(radius);
        for (0..self.height) |y_u| {
            const y: isize = @intCast(y_u);
            for (0..self.width) |x_u| {
                const x: isize = @intCast(x_u);
                var keep = x >= x0 and x < x0 + w and y >= y0 and y < y0 + h;
                if (keep and radius > 0) {
                    const px: f64 = @floatFromInt(x - x0);
                    const py: f64 = @floatFromInt(y - y0);
                    const cx = @min(@max(px, rf), wf - rf);
                    const cy = @min(@max(py, rf), hf - rf);
                    const dx = px - cx;
                    const dy = py - cy;
                    keep = dx * dx + dy * dy <= rf * rf;
                }
                if (!keep) self.pixels[y_u * self.width + x_u] = 0;
            }
        }
    }

    pub fn strokeRoundedRect(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, radius_logical: isize, thickness_logical: f64, r: u8, g: u8, b: u8, a: u8) void {
        const start_x = start_x_logical * self.scale;
        const start_y = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        const radius = radius_logical * self.scale;
        const thickness = thickness_logical * @as(f64, @floatFromInt(self.scale));
        const rad = @as(f64, @floatFromInt(radius));
        const wi = @as(f64, @floatFromInt(w));
        const hi = @as(f64, @floatFromInt(h));
        for (0..@as(usize, @intCast(h))) |y_u| {
            for (0..@as(usize, @intCast(w))) |x_u| {
                const xt = @as(f64, @floatFromInt(x_u)) + 0.5;
                const yt = @as(f64, @floatFromInt(y_u)) + 0.5;

                var alpha: f64 = 1.0;
                var cx: f64 = 0.0;
                var cy: f64 = 0.0;
                if (xt < rad and yt < rad) {
                    cx = rad - xt;
                    cy = rad - yt;
                } else if (xt > wi - rad and yt < rad) {
                    cx = xt - (wi - rad);
                    cy = rad - yt;
                } else if (xt < rad and yt > hi - rad) {
                    cx = rad - xt;
                    cy = yt - (hi - rad);
                } else if (xt > wi - rad and yt > hi - rad) {
                    cx = xt - (wi - rad);
                    cy = yt - (hi - rad);
                }

                var dist: f64 = 0.0;
                if (cx > 0.0 or cy > 0.0) {
                    dist = @sqrt(cx * cx + cy * cy);
                } else if (xt < thickness) {
                    dist = rad - xt;
                } else if (xt > wi - thickness) {
                    dist = rad - (wi - xt);
                } else if (yt < thickness) {
                    dist = rad - yt;
                } else if (yt > hi - thickness) {
                    dist = rad - (hi - yt);
                } else {
                    continue; // inside body, not stroke
                }

                if (dist > rad) {
                    if (dist > rad + 1.0) alpha = 0.0 else alpha = 1.0 - (dist - rad);
                } else if (dist < rad - thickness) {
                    if (dist < rad - thickness - 1.0) alpha = 0.0 else alpha = (dist - (rad - thickness - 1.0));
                }

                if (alpha > 0.0) {
                    const final_a = @as(u8, @intFromFloat(@as(f64, @floatFromInt(a)) * alpha));
                    self.blendPixel(start_x + @as(isize, @intCast(x_u)), start_y + @as(isize, @intCast(y_u)), r, g, b, final_a);
                }
            }
        }
    }

    pub fn widgetFrame(self: *PixelEngine, start_x_logical: isize, start_y_logical: isize, w_logical: isize, h_logical: isize, radius_logical: isize, strength: f64) void {
        if (strength <= 0) return;
        const start_x = start_x_logical * self.scale;
        const start_y = start_y_logical * self.scale;
        const w = w_logical * self.scale;
        const h = h_logical * self.scale;
        const radius = radius_logical * self.scale;
        const thickness = 1.0 * @as(f64, @floatFromInt(self.scale));
        const rad = @as(f64, @floatFromInt(radius));
        const wi = @as(f64, @floatFromInt(w));
        const hi = @as(f64, @floatFromInt(h));
        for (0..@as(usize, @intCast(h))) |y_u| {
            for (0..@as(usize, @intCast(w))) |x_u| {
                const xt = @as(f64, @floatFromInt(x_u)) + 0.5;
                const yt = @as(f64, @floatFromInt(y_u)) + 0.5;

                var alpha: f64 = 1.0;
                var cx: f64 = 0.0;
                var cy: f64 = 0.0;
                if (xt < rad and yt < rad) {
                    cx = rad - xt;
                    cy = rad - yt;
                } else if (xt > wi - rad and yt < rad) {
                    cx = xt - (wi - rad);
                    cy = rad - yt;
                } else if (xt < rad and yt > hi - rad) {
                    cx = rad - xt;
                    cy = yt - (hi - rad);
                } else if (xt > wi - rad and yt > hi - rad) {
                    cx = xt - (wi - rad);
                    cy = yt - (hi - rad);
                }

                var dist: f64 = 0.0;
                if (cx > 0.0 or cy > 0.0) {
                    dist = @sqrt(cx * cx + cy * cy);
                } else if (xt < thickness) {
                    dist = rad - xt;
                } else if (xt > wi - thickness) {
                    dist = rad - (wi - xt);
                } else if (yt < thickness) {
                    dist = rad - yt;
                } else if (yt > hi - thickness) {
                    dist = rad - (hi - yt);
                } else {
                    continue; // inside body, not stroke
                }

                if (dist > rad) {
                    if (dist > rad + 1.0) alpha = 0.0 else alpha = 1.0 - (dist - rad);
                } else if (dist < rad - thickness) {
                    if (dist < rad - thickness - 1.0) alpha = 0.0 else alpha = (dist - (rad - thickness - 1.0));
                }

                if (alpha > 0.0) {
                    // A directional rim like macOS desktop widgets: strongest
                    // along the top-left, with a quiet bottom-right reflection.
                    const vertical = yt / hi;
                    const horizontal = xt / wi;
                    const light = 50.0 + 72.0 * (1.0 - vertical) * (1.0 - 0.4 * horizontal);
                    const final_a = @as(u8, @intFromFloat(@min(255, light * strength) * alpha));
                    self.blendPixel(start_x + @as(isize, @intCast(x_u)), start_y + @as(isize, @intCast(y_u)), 235, 237, 242, final_a);
                }
            }
        }

        // macOS widgets have a second, very quiet inner catchlight. It makes
        // the frame read as a material edge rather than a drawn gray line.
        if (w_logical > 2 and h_logical > 2 and radius_logical > 1) {
            const inner_alpha: u8 = @intFromFloat(@min(42.0, 32.0 * strength));
            self.strokeRoundedRect(start_x_logical + 1, start_y_logical + 1, w_logical - 2, h_logical - 2, radius_logical - 1, 0.5, 255, 255, 255, inner_alpha);
        }
    }

    // Fractional coverage keeps the advancing edge smooth below one pixel.
    pub fn fillProgress(self: *PixelEngine, x_logical: isize, y_logical: isize, width_logical: f64, track_width_logical: f64, height_logical: isize, color: u8) void {
        const x = x_logical * self.scale;
        const y = y_logical * self.scale;
        const width = width_logical * @as(f64, @floatFromInt(self.scale));
        const track_width = track_width_logical * @as(f64, @floatFromInt(self.scale));
        const height = height_logical * self.scale;
        if (width <= 0) return;
        const h: f64 = @floatFromInt(height);
        const radius = @min(track_width, h) / 2;
        for (0..@as(usize, @intFromFloat(@ceil(h)))) |iy| {
            for (0..@as(usize, @intFromFloat(@ceil(width)))) |ix| {
                const px = @as(f64, @floatFromInt(ix)) + 0.5;
                const py = @as(f64, @floatFromInt(iy)) + 0.5;
                const dx = @abs(px - track_width / 2) - (track_width / 2 - radius);
                const dy = @abs(py - h / 2) - (h / 2 - radius);
                const outside = @sqrt(@max(dx, 0) * @max(dx, 0) + @max(dy, 0) * @max(dy, 0));
                const distance = outside + @min(@max(dx, dy), 0) - radius;
                // Clip the full capsule at a flat, fractional progress boundary.
                const coverage = @min(@min(1, @max(0, 0.5 - distance)), @min(1, @max(0, width - @as(f64, @floatFromInt(ix)))));
                self.blendPixel(x + @as(isize, @intCast(ix)), y + @as(isize, @intCast(iy)), color, color, color, @intFromFloat(255 * coverage));
            }
        }
    }

    pub fn drawPlayIcon(self: *PixelEngine, cx: isize, cy: isize, size: usize, r: u8, g: u8, b: u8, a: u8) void {
        const s_f = @as(f64, @floatFromInt(size));
        const limit = size + 6;
        const tri_w = s_f * 1.5;
        const tri_h = s_f * 1.8;
        const vis_offset = tri_w * 0.15;

        for (0..(limit * 2)) |y_u| {
            const y = @as(isize, @intCast(y_u));
            const dy = @as(f64, @floatFromInt(y)) - @as(f64, @floatFromInt(limit));
            for (0..(limit * 2)) |x_u| {
                const x = @as(isize, @intCast(x_u));
                const dx = @as(f64, @floatFromInt(x)) - @as(f64, @floatFromInt(limit));
                var hits: usize = 0;
                for (0..4) |sy| {
                    for (0..4) |sx| {
                        const s_dx = dx + (@as(f64, @floatFromInt(sx)) / 4.0);
                        const s_dy = dy + (@as(f64, @floatFromInt(sy)) / 4.0);
                        const px = s_dx - vis_offset;

                        if (px >= -tri_w / 2.0 and px <= tri_w / 2.0) {
                            const progress = (px + tri_w / 2.0) / tri_w;
                            const max_y = (tri_h / 2.0) * (1.0 - progress);
                            if (@abs(s_dy) <= max_y) {
                                hits += 1;
                            }
                        }
                    }
                }
                if (hits > 0) {
                    const final_a = @as(usize, a) * hits / 16;
                    self.blendPixel(cx + x - @as(isize, @intCast(limit)), cy + y - @as(isize, @intCast(limit)), r, g, b, @as(u8, @intCast(final_a)));
                }
            }
        }
    }

    pub fn drawPauseIcon(self: *PixelEngine, cx: isize, cy: isize, size: usize, r: u8, g: u8, b: u8, a: u8) void {
        const s = @as(isize, @intCast(size));
        const w = @max(3, @divTrunc(s, 2));
        const gap = @max(2, @divTrunc(s, 5));
        self.fillRoundedRect(cx - gap - w, cy - s, w, s * 2, 2, r, g, b, a);
        self.fillRoundedRect(cx + gap, cy - s, w, s * 2, 2, r, g, b, a);
    }

    pub fn drawNextIcon(self: *PixelEngine, cx: isize, cy: isize, size: usize, r: u8, g: u8, b: u8, a: u8) void {
        self.drawSkipIcon(cx, cy, size, false, r, g, b, a);
    }

    pub fn drawPrevIcon(self: *PixelEngine, cx: isize, cy: isize, size: usize, r: u8, g: u8, b: u8, a: u8) void {
        self.drawSkipIcon(cx, cy, size, true, r, g, b, a);
    }

    fn drawSkipIcon(self: *PixelEngine, cx: isize, cy: isize, size: usize, reverse: bool, r: u8, g: u8, b: u8, a: u8) void {
        const half_h = @as(f64, @floatFromInt(size)) * 0.55;
        const tri_w = @as(f64, @floatFromInt(size)) * 0.85;
        const extent = @as(isize, @intCast(size + 2));
        for (0..@as(usize, @intCast(extent * 2))) |y| {
            for (0..@as(usize, @intCast(extent * 2))) |x| {
                var hits: usize = 0;
                for (0..4) |sy| {
                    for (0..4) |sx| {
                        var dx = @as(f64, @floatFromInt(@as(isize, @intCast(x)) - extent)) + (@as(f64, @floatFromInt(sx)) + 0.5) / 4.0;
                        const dy = @as(f64, @floatFromInt(@as(isize, @intCast(y)) - extent)) + (@as(f64, @floatFromInt(sy)) + 0.5) / 4.0;
                        if (reverse) dx = -dx;
                        const local = dx + tri_w;
                        if (local >= 0 and local < tri_w * 2) {
                            const tx = if (local < tri_w) local else local - tri_w;
                            if (@abs(dy) <= half_h * (1.0 - tx / tri_w)) hits += 1;
                        }
                    }
                }
                if (hits > 0) self.blendPixel(cx + @as(isize, @intCast(x)) - extent, cy + @as(isize, @intCast(y)) - extent, r, g, b, @intCast(@as(usize, a) * hits / 16));
            }
        }
    }
    pub fn blitBMP(self: *PixelEngine, bmp_data: []const u8, px_logical: isize, py_logical: isize, dest_size_logical: isize, border_radius_logical: isize) void {
        const px = px_logical * self.scale;
        const py = py_logical * self.scale;
        const dest_size = dest_size_logical * self.scale;
        const border_radius = border_radius_logical * self.scale;
        if (bmp_data.len < 54) return;
        const width = std.mem.readInt(i32, bmp_data[18..22], .little);
        const height_signed = std.mem.readInt(i32, bmp_data[22..26], .little);
        const bpp = std.mem.readInt(u16, bmp_data[28..30], .little);
        const offset = std.mem.readInt(u32, bmp_data[10..14], .little);

        if (bpp != 24 or width <= 0 or height_signed == 0 or height_signed == -2147483648 or dest_size <= 0) return;

        const w = @as(usize, @intCast(width));
        const abs_h = @as(usize, @intCast(if (height_signed < 0) -height_signed else height_signed));
        const is_top_down = (height_signed < 0);

        const row_stride = (w * 3 + 3) & ~@as(usize, 3);

        if (offset > bmp_data.len or abs_h > (bmp_data.len - offset) / row_stride) return;
        const rs_y = @as(f64, @floatFromInt(abs_h)) / @as(f64, @floatFromInt(dest_size));
        const rs_x = @as(f64, @floatFromInt(w)) / @as(f64, @floatFromInt(dest_size));
        const rad = @as(f64, @floatFromInt(border_radius));
        const sz = @as(f64, @floatFromInt(dest_size));

        for (0..@as(usize, @intCast(dest_size))) |y_d| {
            const yt = @as(f64, @floatFromInt(y_d)) + 0.5;
            const top = @as(f64, @floatFromInt(y_d)) * rs_y;
            const bottom = @min(@as(f64, @floatFromInt(abs_h)), top + rs_y);
            for (0..@as(usize, @intCast(dest_size))) |x_d| {
                const left = @as(f64, @floatFromInt(x_d)) * rs_x;
                const right = @min(@as(f64, @floatFromInt(w)), left + rs_x);
                var channels = [_]f64{ 0, 0, 0 };
                var total: f64 = 0;
                // Integrate the source footprint instead of dropping pixels as
                // the pause animation changes size. This suppresses aliasing.
                for (@as(usize, @intFromFloat(top))..@as(usize, @intFromFloat(@ceil(bottom)))) |sy| {
                    const weight_y = @min(bottom, @as(f64, @floatFromInt(sy + 1))) - @max(top, @as(f64, @floatFromInt(sy)));
                    const source_y = if (is_top_down) sy else abs_h - 1 - sy;
                    for (@as(usize, @intFromFloat(left))..@as(usize, @intFromFloat(@ceil(right)))) |sx| {
                        const weight_x = @min(right, @as(f64, @floatFromInt(sx + 1))) - @max(left, @as(f64, @floatFromInt(sx)));
                        const weight = weight_x * weight_y;
                        const index = offset + source_y * row_stride + sx * 3;
                        for (0..3) |channel| channels[channel] += @as(f64, @floatFromInt(bmp_data[index + channel])) * weight;
                        total += weight;
                    }
                }
                const b_col: u8 = @intFromFloat(@min(255, channels[0] / total + 0.5));
                const g_col: u8 = @intFromFloat(@min(255, channels[1] / total + 0.5));
                const r_col: u8 = @intFromFloat(@min(255, channels[2] / total + 0.5));

                const xt = @as(f64, @floatFromInt(x_d)) + 0.5;
                var alpha: f64 = 1.0;

                if (border_radius > 0) {
                    var cx: f64 = 0.0;
                    var cy: f64 = 0.0;
                    if (xt < rad and yt < rad) {
                        cx = rad - xt;
                        cy = rad - yt;
                    } else if (xt > sz - rad and yt < rad) {
                        cx = xt - (sz - rad);
                        cy = rad - yt;
                    } else if (xt < rad and yt > sz - rad) {
                        cx = rad - xt;
                        cy = yt - (sz - rad);
                    } else if (xt > sz - rad and yt > sz - rad) {
                        cx = xt - (sz - rad);
                        cy = yt - (sz - rad);
                    }

                    if (cx > 0.0 or cy > 0.0) {
                        const dist = @sqrt(cx * cx + cy * cy);
                        if (dist > rad) {
                            if (dist > rad + 1.0) {
                                alpha = 0.0;
                            } else {
                                alpha = (rad + 1.0) - dist;
                            }
                        }
                    }
                }

                if (alpha > 0.0) {
                    const final_a = @as(u8, @intFromFloat(255.0 * alpha));
                    self.blendPixel(px + @as(isize, @intCast(x_d)), py + @as(isize, @intCast(y_d)), r_col, g_col, b_col, final_a);
                }
            }
        }
    }

    pub fn drawDropShadow(self: *PixelEngine, x: isize, y: isize, w: isize, h: isize, blur_radius: isize, r: u8, g: u8, b: u8, a: u8) void {
        const rad = @as(f64, @floatFromInt(blur_radius));

        const outer_x = x - blur_radius;
        const outer_y = y - blur_radius;
        const outer_w = w + blur_radius * 2;
        const outer_h = h + blur_radius * 2;

        for (0..@as(usize, @intCast(outer_h))) |dy_u| {
            const dy = @as(isize, @intCast(dy_u));
            const py = outer_y + dy;
            const y_dist = if (py < y) @as(f64, @floatFromInt(y - py)) else if (py > y + h) @as(f64, @floatFromInt(py - (y + h))) else 0.0;

            for (0..@as(usize, @intCast(outer_w))) |dx_u| {
                const dx = @as(isize, @intCast(dx_u));
                const px = outer_x + dx;

                const x_dist = if (px < x) @as(f64, @floatFromInt(x - px)) else if (px > x + w) @as(f64, @floatFromInt(px - (x + w))) else 0.0;

                const dist = @sqrt(x_dist * x_dist + y_dist * y_dist);
                if (dist <= rad) {
                    // Exponential falloff for softer shadow
                    const normalized = dist / rad;
                    const intensity = 1.0 - (normalized * normalized);
                    const final_a = @as(u8, @intFromFloat(@as(f64, @floatFromInt(a)) * intensity));
                    if (final_a > 0) {
                        self.blendPixel(px, py, r, g, b, final_a);
                    }
                }
            }
        }
    }
};

test "artwork downscaling averages details instead of aliasing" {
    var bmp = [_]u8{0} ** 70;
    std.mem.writeInt(i32, bmp[18..22], 2, .little);
    std.mem.writeInt(i32, bmp[22..26], 2, .little);
    std.mem.writeInt(u16, bmp[28..30], 24, .little);
    std.mem.writeInt(u32, bmp[10..14], 54, .little);
    // Two white and two black pixels, with BMP row padding.
    @memset(bmp[54..57], 255);
    @memset(bmp[65..68], 255);
    var engine = try PixelEngine.init(std.testing.allocator, 1, 1);
    defer engine.deinit(std.testing.allocator);
    engine.blitBMP(&bmp, 0, 0, 1, 0);
    const pixel = std.mem.toBytes(engine.pixels[0]);
    try std.testing.expectEqual(@as(u8, 128), pixel[0]);
    try std.testing.expectEqual(@as(u8, 128), pixel[1]);
    try std.testing.expectEqual(@as(u8, 128), pixel[2]);
    try std.testing.expectEqual(@as(u8, 255), pixel[3]);
}

test "blendPixel alpha channel compositing" {
    var engine = try PixelEngine.init(std.testing.allocator, 2, 2);
    defer engine.deinit(std.testing.allocator);

    // Initial state is all 0
    try std.testing.expectEqual(@as(u32, 0), engine.pixels[0]);

    // Opaque red (r=255, g=0, b=0, a=255)
    engine.blendPixel(0, 0, 255, 0, 0, 255);
    const p1 = std.mem.toBytes(engine.pixels[0]);
    try std.testing.expectEqual(@as(u8, 255), p1[0]);
    try std.testing.expectEqual(@as(u8, 0), p1[1]);
    try std.testing.expectEqual(@as(u8, 0), p1[2]);
    try std.testing.expectEqual(@as(u8, 255), p1[3]);

    // Zero-alpha blend does not alter pixel
    engine.blendPixel(0, 0, 0, 255, 0, 0);
    try std.testing.expectEqual(p1, std.mem.toBytes(engine.pixels[0]));
}

test "blendPixel respects canvas bounds without overflow" {
    var engine = try PixelEngine.init(std.testing.allocator, 4, 4);
    defer engine.deinit(std.testing.allocator);

    // Out of bounds writes must safely be ignored
    engine.blendPixel(-1, 0, 255, 255, 255, 255);
    engine.blendPixel(0, -1, 255, 255, 255, 255);
    engine.blendPixel(4, 0, 255, 255, 255, 255);
    engine.blendPixel(0, 4, 255, 255, 255, 255);

    for (engine.pixels) |p| {
        try std.testing.expectEqual(@as(u32, 0), p);
    }
}

test "fillRoundedRect modifies canvas within bounds" {
    var engine = try PixelEngine.init(std.testing.allocator, 10, 10);
    defer engine.deinit(std.testing.allocator);

    engine.fillRoundedRect(1, 1, 8, 8, 2, 255, 255, 255, 255);
    // Center pixel (5, 5) must be painted
    const center_pixel = std.mem.toBytes(engine.pixels[5 * 10 + 5]);
    try std.testing.expectEqual(@as(u8, 255), center_pixel[3]);

    // Outer corner (0, 0) must NOT be painted
    const corner_pixel = std.mem.toBytes(engine.pixels[0]);
    try std.testing.expectEqual(@as(u8, 0), corner_pixel[3]);
}
