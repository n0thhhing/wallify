const std = @import("std");
const macos = @import("../macos.zig");

// 4. Artwork Glow
const W: usize = 320;
const H: usize = 220;

var glow_current: macos.Ref = null;
var glow_previous: macos.Ref = null;
var glow_modified: std.posix.timespec = .{ .sec = 0, .nsec = 0 };
var glow_changed_at: f64 = 0;
var float_buf: [320 * 220 * 4]f32 = undefined;

fn makeGlow() macos.Ref {
    const path = "/tmp/art.bmp";
    const url = macos.CFURLCreateFromFileSystemRepresentation(null, path.ptr, path.len, 0);
    if (url == null) return null;
    defer macos.CFRelease(url);

    const source = macos.CGImageSourceCreateWithURL(url, null);
    if (source == null) return null;
    defer macos.CFRelease(source);

    const art = macos.CGImageSourceCreateImageAtIndex(source, 0, null);
    if (art == null) return null;
    defer macos.CGImageRelease(art);

    const space = macos.CGColorSpaceCreateDeviceRGB();
    const bitmap = macos.CGBitmapContextCreate(null, W, H, 8, W * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    macos.CGColorSpaceRelease(space);
    if (bitmap == null) return null;
    defer macos.CGContextRelease(bitmap);

    const bounds = macos.rect(0, 0, @floatFromInt(W), @floatFromInt(H));
    macos.CGContextDrawImage(bitmap, bounds, art);

    const raw = macos.CGBitmapContextGetData(bitmap) orelse return null;
    const data: [*]u8 = @ptrCast(raw);

    for (0..H) |y| {
        for (0..W) |x| {
            for (0..4) |c| {
                float_buf[(y * W + x) * 4 + c] = @floatFromInt(data[(y * W + x) * 4 + c]);
            }
        }
    }

    const radius: isize = 14;
    var temp: [320 * 220 * 4]f32 = undefined;

    for (0..H) |y| {
        for (0..W) |x| {
            for (0..4) |c| {
                var sum: f32 = 0;
                var total: f32 = 0;
                var dy: isize = -radius;
                while (dy <= radius) : (dy += 1) {
                    const ny = @as(isize, @intCast(y)) + dy;
                    if (ny >= 0 and ny < @as(isize, @intCast(H))) {
                        const dist = @as(f32, @floatFromInt(dy * dy));
                        const weight = @exp(-dist / (2 * 6 * 6));
                        sum += float_buf[(@as(usize, @intCast(ny)) * W + x) * 4 + c] * weight;
                        total += weight;
                    }
                }
                temp[(y * W + x) * 4 + c] = if (total > 0) sum / total else 0;
            }
        }
    }

    for (0..H) |y| {
        for (0..W) |x| {
            for (0..4) |c| {
                var sum: f32 = 0;
                var total: f32 = 0;
                var dx: isize = -radius;
                while (dx <= radius) : (dx += 1) {
                    const nx = @as(isize, @intCast(x)) + dx;
                    if (nx >= 0 and nx < @as(isize, @intCast(W))) {
                        const dist = @as(f32, @floatFromInt(dx * dx));
                        const weight = @exp(-dist / (2 * 6 * 6));
                        sum += temp[(y * W + @as(usize, @intCast(nx))) * 4 + c] * weight;
                        total += weight;
                    }
                }
                var value = if (total > 0) sum / total else 0;
                if (c == 3) {
                    value = @min(255.0, value * 1.8);
                }
                data[(y * W + x) * 4 + c] = @intFromFloat(@round(value));
            }
        }
    }

    return macos.CGBitmapContextCreateImage(bitmap);
}

pub export fn widget_artwork_glow(pixels: [*]u32, w: usize, h: usize, card_width: f64, card_height: f64, scale: f64, opacity: f64, now: f64, animations: c_int) callconv(.c) void {
    var info: std.posix.Stat = undefined;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/art.bmp", .{ .ACCMODE = .RDONLY }, 0) catch -1;
    if (fd >= 0) {
        defer _ = std.posix.system.close(fd);
        if (std.posix.system.fstat(fd, &info) == 0 and (glow_current == null or info.mtimespec.sec != glow_modified.sec or info.mtimespec.nsec != glow_modified.nsec)) {
            const next = makeGlow();
            if (next != null) {
                if (glow_previous != null) macos.CGImageRelease(glow_previous);
                glow_previous = glow_current;
                glow_current = next;
                glow_modified = info.mtimespec;
                glow_changed_at = now;
            }
        }
    }

    if (glow_current == null or opacity <= 0) return;

    const space = macos.CGColorSpaceCreateDeviceRGB();
    const ctx = macos.CGBitmapContextCreate(pixels, w, h, 8, w * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    macos.CGColorSpaceRelease(space);
    if (ctx == null) return;
    defer macos.CGContextRelease(ctx);

    const fh: f64 = @floatFromInt(h);
    macos.CGContextTranslateCTM(ctx, 0, fh);
    macos.CGContextScaleCTM(ctx, scale, -scale);

    const clip = macos.CGPathCreateWithRoundedRect(macos.rect(0, 0, card_width, card_height), 26, 26, null);
    macos.CGContextAddPath(ctx, clip);
    macos.CGContextClip(ctx);
    macos.CGPathRelease(clip);

    var progress: f64 = if (animations != 0) (now - glow_changed_at) / 0.5 else 1.0;
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
    const t = progress * progress * progress * (10.0 + progress * (-15.0 + 6.0 * progress));

    macos.CGContextSetAlpha(ctx, opacity * 0.5);
    macos.CGContextBeginTransparencyLayer(ctx, null);
    defer macos.CGContextEndTransparencyLayer(ctx);

    macos.CGContextSetBlendMode(ctx, macos.kCGBlendModePlusLighter);
    macos.CGContextTranslateCTM(ctx, 0, 200);
    macos.CGContextScaleCTM(ctx, 1, -1);

    if (glow_previous != null and t < 1.0) {
        macos.CGContextSetAlpha(ctx, 1.0 - t);
        macos.CGContextDrawImage(ctx, macos.rect(-120, -120, 640, 440), glow_previous);
    }
    macos.CGContextSetAlpha(ctx, if (glow_previous != null) t else 1.0);
    macos.CGContextDrawImage(ctx, macos.rect(-120, -120, 640, 440), glow_current);
}
