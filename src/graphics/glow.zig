const std = @import("std");
const macos = @import("../platform/macos.zig");

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

    macos.CGContextScaleCTM(bitmap, 0.5, 0.5);
    macos.CGContextTranslateCTM(bitmap, 220, 220);
    macos.CGContextRotateCTM(bitmap, -92.0 * std.math.pi / 180.0);
    macos.CGContextScaleCTM(bitmap, 1.3, 1.4);
    macos.CGContextSaveGState(bitmap);
    const art_clip = macos.CGPathCreateWithRoundedRect(macos.rect(-76, -76, 152, 152), 14, 14, null);
    macos.CGContextAddPath(bitmap, art_clip);
    macos.CGContextClip(bitmap);
    macos.CGPathRelease(art_clip);
    macos.CGContextDrawImage(bitmap, macos.rect(-76, -76, 152, 152), art);
    macos.CGContextRestoreGState(bitmap);

    const data: [*]u8 = @ptrCast(macos.CGBitmapContextGetData(bitmap) orelse return null);

    const KSIZE: usize = 121;
    const KHALF: isize = 60;
    var kernel: [KSIZE]f32 = undefined;
    var sum: f32 = 0;
    for (0..KSIZE) |i| {
        const k = @as(f32, @floatFromInt(i)) - 60.0;
        kernel[i] = @exp(-(k * k) / (2.0 * 20.0 * 20.0));
        sum += kernel[i];
    }
    for (0..KSIZE) |i| kernel[i] /= sum;

    for (0..H) |y| {
        for (0..W) |x| {
            for (0..4) |c| {
                var value: f32 = 0;
                for (0..KSIZE) |i| {
                    const xx: isize = @as(isize, @intCast(x)) + @as(isize, @intCast(i)) - KHALF;
                    if (xx >= 0 and xx < W) {
                        const u_xx: usize = @intCast(xx);
                        value += @as(f32, @floatFromInt(data[(y * W + u_xx) * 4 + c])) * kernel[i];
                    }
                }
                float_buf[(y * W + x) * 4 + c] = value;
            }
        }
    }

    for (0..H) |y| {
        for (0..W) |x| {
            for (0..4) |c| {
                var value: f32 = 0;
                for (0..KSIZE) |i| {
                    const yy: isize = @as(isize, @intCast(y)) + @as(isize, @intCast(i)) - KHALF;
                    if (yy >= 0 and yy < H) {
                        const u_yy: usize = @intCast(yy);
                        value += float_buf[(u_yy * W + x) * 4 + c] * kernel[i];
                    }
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
