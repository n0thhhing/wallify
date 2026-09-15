const std = @import("std");
const macos = @import("../platform/macos.zig");

pub const IconKind = enum(c_int) {
    play = 0,
    pause = 1,
    prev = 2,
    next = 3,
};

var symbol_images: [4]macos.Ref = .{ null, null, null, null };
var symbol_sizes: [4]macos.Size = .{ .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 } };
var symbol_once: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn initSymbols() void {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    const names = [_][]const u8{ "play.fill", "pause.fill", "backward.fill", "forward.fill" };
    const img_cls = macos.objc_getClass("NSImage");
    const cfg_cls = macos.objc_getClass("NSImageSymbolConfiguration");

    for (names, 0..) |name, i| {
        const pt_size: f64 = if (i < 2) 28.0 else 17.0;

        const name_str = macos.string(name);
        defer macos.CFRelease(name_str);
        var img = macos.send(macos.Ref, img_cls, "imageWithSystemSymbolName:accessibilityDescription:", .{ name_str, @as(macos.Ref, null) });
        if (img == null) continue;

        const cfg = macos.send(macos.Ref, cfg_cls, "configurationWithPointSize:weight:", .{ pt_size, @as(f64, 0.0) });
        img = macos.send(macos.Ref, img, "imageWithSymbolConfiguration:", .{cfg});
        if (img == null) continue;

        const sz = macos.send(macos.Size, img, "size", .{});
        const raster_sz = macos.Size{ .width = sz.width * 3, .height = sz.height * 3 };

        const raster = macos.send(macos.Ref, macos.send(macos.Ref, img_cls, "alloc", .{}), "initWithSize:", .{raster_sz});
        macos.send(void, raster, "lockFocus", .{});
        macos.send(void, img, "drawInRect:fromRect:operation:fraction:", .{
            macos.rect(0, 0, raster_sz.width, raster_sz.height),
            macos.rect(0, 0, 0, 0),
            @as(usize, 2),
            @as(f64, 1.0),
        });
        macos.send(void, raster, "unlockFocus", .{});

        const cg = macos.send(macos.Ref, raster, "CGImageForProposedRect:context:hints:", .{
            @as(?*macos.Rect, null),
            @as(macos.Ref, null),
            @as(macos.Ref, null),
        });
        if (cg != null) {
            symbol_images[i] = macos.CGImageRetain(cg);
            symbol_sizes[i] = sz;
        }
    }
}

pub export fn widget_draw_symbol(context: macos.Ref, kind: IconKind) callconv(.c) c_int {
    if (!symbol_once.swap(true, .monotonic)) {
        initSymbols();
    }
    const idx: usize = @intCast(@intFromEnum(kind));
    if (idx >= symbol_images.len or symbol_images[idx] == null) return 0;
    const sz = symbol_sizes[idx];
    const r = macos.rect(-sz.width / 2.0, -sz.height / 2.0, sz.width, sz.height);
    macos.CGContextSaveGState(context);
    macos.CGContextClipToMask(context, r, symbol_images[idx]);
    macos.CGContextFillRect(context, r);
    macos.CGContextRestoreGState(context);
    return 1;
}

pub fn rounded_triangle(context: macos.Ref, x: f64, y: f64, w: f64, h: f64) void {
    macos.CGContextBeginPath(context);
    macos.CGContextMoveToPoint(context, x, y - h / 2.0);
    macos.CGContextAddLineToPoint(context, x + w, y);
    macos.CGContextAddLineToPoint(context, x, y + h / 2.0);
    macos.CGContextClosePath(context);
    macos.CGContextDrawPath(context, macos.kCGPathFillStroke);
}

pub export fn widget_icon(pixels: [*]u32, width: usize, height: usize, x: f64, y: f64, kind: IconKind, hover: f64, opacity: f64, scale: f64) callconv(.c) void {
    _ = hover;
    const space = macos.CGColorSpaceCreateDeviceRGB();
    const c = macos.CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    macos.CGColorSpaceRelease(space);
    if (c == null) return;
    defer macos.CGContextRelease(c);

    macos.CGContextTranslateCTM(c, x, @as(f64, @floatFromInt(height)) - y);
    macos.CGContextScaleCTM(c, scale, scale);
    macos.CGContextSetAlpha(c, opacity);
    macos.CGContextBeginTransparencyLayer(c, null);
    defer macos.CGContextEndTransparencyLayer(c);

    const color: f64 = 0.83;
    macos.CGContextSetRGBFillColor(c, color, color, color, 1.0);
    macos.CGContextSetRGBStrokeColor(c, color, color, color, 1.0);
    macos.CGContextSetLineJoin(c, macos.kCGLineJoinRound);
    macos.CGContextSetLineWidth(c, 1.6);

    if (widget_draw_symbol(c, kind) != 0) {
        // Native symbol drawn
    } else switch (kind) {
        .play => rounded_triangle(c, -7, 0, 18, 23),
        .pause => {
            const left = macos.CGPathCreateWithRoundedRect(macos.rect(-8, -12, 6, 24), 1.8, 1.8, null);
            const right = macos.CGPathCreateWithRoundedRect(macos.rect(2, -12, 6, 24), 1.8, 1.8, null);
            macos.CGContextAddPath(c, left);
            macos.CGContextAddPath(c, right);
            macos.CGContextFillPath(c);
            macos.CGPathRelease(left);
            macos.CGPathRelease(right);
        },
        .prev => {
            macos.CGContextScaleCTM(c, -1, 1);
            rounded_triangle(c, -8, 0, 9, 12);
            rounded_triangle(c, 2, 0, 9, 12);
        },
        .next => {
            rounded_triangle(c, -8, 0, 9, 12);
            rounded_triangle(c, 2, 0, 9, 12);
        },
    }
}

var spotify_app_icon: macos.Ref = null;

pub fn getSpotifyAppIcon() macos.Ref {
    if (spotify_app_icon != null) return spotify_app_icon;

    const paths = [_][]const u8{
        "/Applications/Spotify.app/Contents/Resources/AppIcon.icns",
        "assets/spotify_icon.png",
    };
    for (paths) |path| {
        const url = macos.CFURLCreateFromFileSystemRepresentation(null, path.ptr, @as(isize, @intCast(path.len)), 0);
        if (url != null) {
            defer macos.CFRelease(url);
            const src = macos.CGImageSourceCreateWithURL(url, null);
            if (src != null) {
                defer macos.CFRelease(src);
                spotify_app_icon = macos.CGImageSourceCreateImageAtIndex(src, 0, null);
                if (spotify_app_icon != null) return spotify_app_icon;
            }
        }
    }
    return null;
}

pub export fn widget_spotify_icon(pixels: [*]u32, width: usize, height: usize, x: f64, y: f64, size: f64) callconv(.c) c_int {
    const icon = getSpotifyAppIcon();
    if (icon == null) return 0;

    const space = macos.CGColorSpaceCreateDeviceRGB();
    const ctx = macos.CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    macos.CGColorSpaceRelease(space);
    if (ctx == null) return 0;
    defer macos.CGContextRelease(ctx);

    const fh: f64 = @floatFromInt(height);
    const dest_rect = macos.rect(x, fh - y - size, size, size);
    macos.CGContextDrawImage(ctx, dest_rect, icon);
    return 1;
}
