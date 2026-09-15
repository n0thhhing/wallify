const std = @import("std");
const Ref = @import("core_foundation.zig").Ref;

pub const Point = extern struct { x: f64, y: f64 };
pub const Size = extern struct { width: f64, height: f64 };
pub const Rect = extern struct { origin: Point, size: Size };

pub fn rect(x: f64, y: f64, w: f64, h: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}

pub extern "c" var kCGWindowBounds: Ref;
pub extern "c" var kCGWindowName: Ref;
pub extern "c" var kCGWindowOwnerName: Ref;
pub extern "c" var kCGWindowLayer: Ref;
pub extern "c" var kCGWindowNumber: Ref;
pub extern "c" var kCGWindowAlpha: Ref;

pub extern "c" fn CGWindowListCopyWindowInfo(option: u32, relative_to_window: u32) Ref;
pub extern "c" fn CGRectMakeWithDictionaryRepresentation(dict: Ref, out_rect: *Rect) bool;

pub extern "c" fn CGColorSpaceCreateDeviceRGB() Ref;
pub extern "c" fn CGColorSpaceRelease(space: Ref) void;
pub extern "c" fn CGColorCreate(space: Ref, components: [*]const f64) Ref;
pub extern "c" fn CGColorRelease(color: Ref) void;

pub extern "c" fn CGBitmapContextCreate(data: Ref, width: usize, height: usize, bitsPerComponent: usize, bytesPerRow: usize, space: Ref, bitmapInfo: u32) Ref;
pub extern "c" fn CGBitmapContextGetData(context: Ref) Ref;
pub extern "c" fn CGBitmapContextCreateImage(context: Ref) Ref;
pub extern "c" fn CGContextRelease(c: Ref) void;

pub extern "c" fn CGContextTranslateCTM(c: Ref, tx: f64, ty: f64) void;
pub extern "c" fn CGContextScaleCTM(c: Ref, sx: f64, sy: f64) void;
pub extern "c" fn CGContextRotateCTM(c: Ref, angle: f64) void;
pub extern "c" fn CGContextSetAlpha(c: Ref, alpha: f64) void;
pub extern "c" fn CGContextSetBlendMode(c: Ref, mode: u32) void;
pub extern "c" fn CGContextBeginTransparencyLayer(c: Ref, auxInfo: Ref) void;
pub extern "c" fn CGContextEndTransparencyLayer(c: Ref) void;
pub extern "c" fn CGContextSetRGBFillColor(c: Ref, red: f64, green: f64, blue: f64, alpha: f64) void;
pub extern "c" fn CGContextSetRGBStrokeColor(c: Ref, red: f64, green: f64, blue: f64, alpha: f64) void;
pub extern "c" fn CGContextSetLineJoin(c: Ref, join: u32) void;
pub extern "c" fn CGContextSetLineWidth(c: Ref, width: f64) void;
pub extern "c" fn CGContextSetShouldAntialias(c: Ref, shouldAntialias: bool) void;
pub extern "c" fn CGContextSetTextPosition(c: Ref, x: f64, y: f64) void;
pub extern "c" fn CGContextClipToRect(c: Ref, r: Rect) void;
pub extern "c" fn CGContextClipToMask(c: Ref, r: Rect, mask: Ref) void;
pub extern "c" fn CGContextFillRect(c: Ref, r: Rect) void;
pub extern "c" fn CGContextDrawImage(c: Ref, r: Rect, image: Ref) void;
pub extern "c" fn CGContextSaveGState(c: Ref) void;
pub extern "c" fn CGContextRestoreGState(c: Ref) void;
pub extern "c" fn CGContextBeginPath(c: Ref) void;
pub extern "c" fn CGContextMoveToPoint(c: Ref, x: f64, y: f64) void;
pub extern "c" fn CGContextAddLineToPoint(c: Ref, x: f64, y: f64) void;
pub extern "c" fn CGContextClosePath(c: Ref) void;
pub extern "c" fn CGContextDrawPath(c: Ref, mode: u32) void;
pub extern "c" fn CGContextAddPath(c: Ref, path: Ref) void;
pub extern "c" fn CGContextClip(c: Ref) void;
pub extern "c" fn CGContextFillPath(c: Ref) void;

pub extern "c" fn CGPathCreateWithRoundedRect(r: Rect, cornerWidth: f64, cornerHeight: f64, transform: Ref) Ref;
pub extern "c" fn CGPathRelease(path: Ref) void;
pub extern "c" fn CGImageRetain(image: Ref) Ref;
pub extern "c" fn CGImageRelease(image: Ref) void;
pub extern "c" fn CGImageSourceCreateWithURL(url: Ref, options: Ref) Ref;
pub extern "c" fn CGImageSourceCreateImageAtIndex(isrc: Ref, index: usize, options: Ref) Ref;

pub const kCGImageAlphaPremultipliedLast: u32 = 1;
pub const kCGBitmapByteOrder32Big: u32 = (4 << 12);
pub const kCGBlendModePlusLighter: u32 = 21;
pub const kCGPathFillStroke: u32 = 3;
pub const kCGLineJoinRound: u32 = 1;
