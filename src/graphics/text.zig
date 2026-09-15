const std = @import("std");
const macos = @import("../platform/macos.zig");

pub export fn widget_text_width(utf8: [*]const u8, length: usize, font_size: f64, bold: c_int) callconv(.c) f64 {
    if (length == 0) return 0;
    const str = macos.CFStringCreateWithBytes(null, utf8, @intCast(length), 0x08000100, 0);
    if (str == null) return 0;
    defer macos.CFRelease(str);
    const font = macos.CTFontCreateUIFontForLanguage(if (bold != 0) macos.kCTFontUIFontEmphasizedSystem else macos.kCTFontUIFontSystem, font_size, null);
    if (font == null) return 0;
    defer macos.CFRelease(font);
    const keys = [_]macos.Ref{macos.kCTFontAttributeName};
    const values = [_]macos.Ref{font};
    const attrs = macos.CFDictionaryCreate(null, &keys, &values, 1, &macos.kCFTypeDictionaryKeyCallBacks, &macos.kCFTypeDictionaryValueCallBacks);
    defer macos.CFRelease(attrs);
    const attr = macos.CFAttributedStringCreate(null, str, attrs);
    defer macos.CFRelease(attr);
    const line = macos.CTLineCreateWithAttributedString(attr);
    defer macos.CFRelease(line);
    return macos.CTLineGetTypographicBounds(line, null, null, null);
}

pub export fn widget_text(pixels: [*]u32, width: usize, height: usize, utf8: [*]const u8, length: usize, x: f64, y: f64, max_width: f64, font_size: f64, bold: c_int, right_align: c_int, r: u8, g: u8, b: u8) callconv(.c) void {
    if (length == 0 or max_width <= 0) return;
    const str = macos.CFStringCreateWithBytes(null, utf8, @intCast(length), 0x08000100, 0);
    if (str == null) return;
    defer macos.CFRelease(str);

    const font = macos.CTFontCreateUIFontForLanguage(if (bold != 0) macos.kCTFontUIFontEmphasizedSystem else macos.kCTFontUIFontSystem, font_size, null);
    if (font == null) return;
    defer macos.CFRelease(font);

    const space = macos.CGColorSpaceCreateDeviceRGB();
    defer macos.CGColorSpaceRelease(space);

    const components = [_]f64{ @as(f64, @floatFromInt(r)) / 255.0, @as(f64, @floatFromInt(g)) / 255.0, @as(f64, @floatFromInt(b)) / 255.0, 1.0 };
    const color = macos.CGColorCreate(space, &components);
    defer macos.CGColorRelease(color);

    const keys = [_]macos.Ref{ macos.kCTFontAttributeName, macos.kCTForegroundColorAttributeName };
    const values = [_]macos.Ref{ font, color };
    const attrs = macos.CFDictionaryCreate(null, &keys, &values, 2, &macos.kCFTypeDictionaryKeyCallBacks, &macos.kCFTypeDictionaryValueCallBacks);
    defer macos.CFRelease(attrs);

    const attr = macos.CFAttributedStringCreate(null, str, attrs);
    defer macos.CFRelease(attr);

    var line = macos.CTLineCreateWithAttributedString(attr);

    if (macos.CTLineGetTypographicBounds(line, null, null, null) > max_width) {
        const dots = macos.string("…");
        defer macos.CFRelease(dots);
        const token_attr = macos.CFAttributedStringCreate(null, dots, attrs);
        defer macos.CFRelease(token_attr);
        const token = macos.CTLineCreateWithAttributedString(token_attr);
        defer macos.CFRelease(token);
        const truncated = macos.CTLineCreateTruncatedLine(line, max_width, macos.kCTLineTruncationEnd, token);
        if (truncated != null) {
            macos.CFRelease(line);
            line = truncated;
        }
    }
    defer macos.CFRelease(line);

    const context = macos.CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    if (context != null) {
        defer macos.CGContextRelease(context);
        var ascent: f64 = 0;
        const line_width = macos.CTLineGetTypographicBounds(line, &ascent, null, null);
        macos.CGContextClipToRect(context, macos.rect(x, 0, max_width, @floatFromInt(height)));
        macos.CGContextSetShouldAntialias(context, true);
        const text_x = x + if (right_align != 0) max_width - line_width else 0;
        const text_y = @as(f64, @floatFromInt(height)) - y - ascent;
        macos.CGContextSetTextPosition(context, text_x, text_y);
        macos.CTLineDraw(line, context);
    }
}
