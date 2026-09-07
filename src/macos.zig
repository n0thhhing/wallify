const std = @import("std");

// Subsystem domain modules
pub const text = @import("graphics/text.zig");
pub const symbols = @import("graphics/symbols.zig");
pub const glow = @import("graphics/glow.zig");
pub const spotify = @import("media/spotify.zig");
pub const menu = @import("ui/menu.zig");
pub const window = @import("ui/window.zig");

// Re-export symbols for backward compatibility
pub const widget_text_width = text.widget_text_width;
pub const widget_text = text.widget_text;
pub const widget_text_clipped = text.widget_text_clipped;

pub const IconKind = symbols.IconKind;
pub const initSymbols = symbols.initSymbols;
pub const widget_icon = symbols.widget_icon;
pub const widget_draw_symbol = symbols.widget_draw_symbol;

pub const widget_artwork_glow = glow.widget_artwork_glow;

pub const SpotifyControl = spotify.SpotifyControl;
pub const widget_is_spotify_running = spotify.widget_is_spotify_running;
pub const widget_spotify_control = spotify.widget_spotify_control;
pub const widget_spotify_seek = spotify.widget_spotify_seek;
pub const widget_query_spotify = spotify.widget_query_spotify;
pub const widget_open_spotify = spotify.widget_open_spotify;
pub const widget_spotify_observe = spotify.widget_spotify_observe;
pub const widget_spotify_take_state = spotify.widget_spotify_take_state;

pub const ContextMenuAction = menu.ContextMenuAction;
pub const widget_context_menu_action = menu.widget_context_menu_action;
pub const ContextMenuCtx = menu.ContextMenuCtx;
pub const widget_context_menu = menu.widget_context_menu;

pub const PanelSnap = window.PanelSnap;
pub const widget_begin_panel_drag = window.widget_begin_panel_drag;
pub const widget_update_panel_drag = window.widget_update_panel_drag;
pub const widget_end_panel_drag = window.widget_end_panel_drag;
pub const widget_panel_grid_x = window.widget_panel_grid_x;
pub const widget_panel_grid_y = window.widget_panel_grid_y;
pub const widget_render_lock = window.widget_render_lock;
pub const widget_render_unlock = window.widget_render_unlock;
pub const widget_terminal_columns = window.widget_terminal_columns;
pub const widget_terminal_rows = window.widget_terminal_rows;
pub const widget_scale_factor = window.widget_scale_factor;
pub const widget_cell_width = window.widget_cell_width;
pub const widget_cell_height = window.widget_cell_height;
pub const widget_monotonic_time = window.widget_monotonic_time;
pub const widget_mouse_location = window.widget_mouse_location;
pub const widget_debug_window_show = window.widget_debug_window_show;
pub const widget_debug_window_hide = window.widget_debug_window_hide;
pub const widget_show_snap_outline = window.widget_show_snap_outline;
pub const widget_set_snap_debug = window.widget_set_snap_debug;
pub const widget_hide_snap_outline = window.widget_hide_snap_outline;
pub const widget_start_drag = window.widget_start_drag;
pub const widget_nearby_panel_snap = window.widget_nearby_panel_snap;
pub const widget_application_init = window.widget_application_init;
pub const widget_application_run = window.widget_application_run;

pub const Ref = ?*anyopaque;

pub const Point = extern struct { x: f64, y: f64 };
pub const Size = extern struct { width: f64, height: f64 };
pub const Rect = extern struct { origin: Point, size: Size };

pub fn rect(x: f64, y: f64, w: f64, h: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}

// CoreFoundation APIs
pub extern "c" fn CFRelease(?*const anyopaque) void;
pub extern "c" fn CFRetain(?*const anyopaque) ?*const anyopaque;
pub extern "c" fn CFStringCreateWithBytes(alloc: Ref, bytes: [*]const u8, numBytes: isize, encoding: u32, isExternalRepresentation: u8) Ref;
pub extern "c" fn CFStringGetCString(theString: Ref, buffer: [*]u8, bufferSize: isize, encoding: u32) u8;
pub extern "c" fn CFStringGetLength(theString: Ref) isize;
pub extern "c" fn CFGetTypeID(cf: Ref) usize;
pub extern "c" fn CFStringGetTypeID() usize;
pub extern "c" fn CFDictionaryGetValue(theDict: Ref, key: ?*const anyopaque) Ref;
pub extern "c" fn CFArrayGetCount(theArray: Ref) isize;
pub extern "c" fn CFArrayGetValueAtIndex(theArray: Ref, idx: isize) Ref;
pub extern "c" fn CFNumberGetValue(number: Ref, numberType: c_int, value: *anyopaque) bool;
pub extern "c" fn CFDictionaryCreate(allocator: Ref, keys: [*]const Ref, values: [*]const Ref, numValues: isize, keyCallBacks: *const anyopaque, valueCallBacks: *const anyopaque) Ref;

pub const DictionaryCallbacks = extern struct {
    version: isize,
    retain: Ref,
    release: Ref,
    copyDescription: Ref,
    equal: Ref,
    hash: Ref,
};

pub extern "c" var kCFTypeDictionaryKeyCallBacks: DictionaryCallbacks;
pub extern "c" var kCFTypeDictionaryValueCallBacks: DictionaryCallbacks;
pub extern "c" var kCGWindowBounds: Ref;
pub extern "c" var kCGWindowName: Ref;
pub extern "c" var kCGWindowOwnerName: Ref;
pub extern "c" var kCGWindowLayer: Ref;
pub extern "c" var kCGWindowNumber: Ref;
pub extern "c" fn CGWindowListCopyWindowInfo(option: u32, relative_to_window: u32) Ref;
pub extern "c" fn CGRectMakeWithDictionaryRepresentation(dict: Ref, out_rect: *Rect) bool;

pub extern "c" fn CFAttributedStringCreate(allocator: Ref, str: Ref, attributes: Ref) Ref;
pub extern "c" fn CFURLCreateFromFileSystemRepresentation(allocator: Ref, buffer: [*]const u8, bufLen: isize, isDirectory: u8) Ref;
pub extern "c" fn CFNotificationCenterGetDistributedCenter() Ref;
pub extern "c" fn CFNotificationCenterAddObserver(center: Ref, observer: Ref, callback: *const fn (Ref, Ref, Ref, Ref, Ref) callconv(.c) void, name: Ref, object: Ref, suspensionBehavior: isize) void;

// CoreGraphics APIs
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
pub extern "c" fn CGContextClipToRect(c: Ref, rect: Rect) void;
pub extern "c" fn CGContextClipToMask(c: Ref, rect: Rect, mask: Ref) void;
pub extern "c" fn CGContextFillRect(c: Ref, rect: Rect) void;
pub extern "c" fn CGContextDrawImage(c: Ref, rect: Rect, image: Ref) void;
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
pub extern "c" fn CGPathCreateWithRoundedRect(rect: Rect, cornerWidth: f64, cornerHeight: f64, transform: Ref) Ref;
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

// CoreText APIs
pub extern "c" var kCTFontAttributeName: Ref;
pub extern "c" var kCTForegroundColorAttributeName: Ref;
pub extern "c" fn CTFontCreateUIFontForLanguage(fontType: u32, size: f64, language: Ref) Ref;
pub extern "c" fn CTLineCreateWithAttributedString(attrString: Ref) Ref;
pub extern "c" fn CTLineGetTypographicBounds(line: Ref, ascent: ?*f64, descent: ?*f64, leading: ?*f64) f64;
pub extern "c" fn CTLineCreateTruncatedLine(line: Ref, width: f64, truncationType: u32, truncationToken: Ref) Ref;
pub extern "c" fn CTLineDraw(line: Ref, context: Ref) void;

pub const kCTFontUIFontSystem: u32 = 0;
pub const kCTFontUIFontEmphasizedSystem: u32 = 2;
pub const kCTLineTruncationEnd: u32 = 2;

// Objective-C Runtime APIs
pub extern "objc" fn objc_getClass(name: [*:0]const u8) Ref;
pub extern "objc" fn sel_registerName(name: [*:0]const u8) Ref;
pub extern "objc" fn objc_msgSend() void;
pub extern "objc" fn objc_allocateClassPair(superclass: Ref, name: [*:0]const u8, extraBytes: usize) Ref;
pub extern "objc" fn objc_registerClassPair(cls: Ref) void;
pub extern "objc" fn class_addMethod(cls: Ref, name: Ref, imp: *const anyopaque, types: [*:0]const u8) bool;
pub extern "c" fn dispatch_async_f(queue: Ref, context: Ref, work: *const fn (Ref) callconv(.c) void) void;
pub extern "c" var _dispatch_main_q: u8;
pub fn dispatch_get_main_queue() Ref {
    return @ptrCast(&_dispatch_main_q);
}

pub fn send0(comptime R: type, obj: Ref, selector: [*:0]const u8) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel);
}

pub fn send1(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a);
}

pub fn send2(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b);
}

pub fn send3(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B, comptime C: type, c: C) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B, C) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b, c);
}

pub fn send4(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B, comptime C: type, c: C, comptime D: type, d: D) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B, C, D) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b, c, d);
}

pub fn string(bytes: []const u8) Ref {
    return CFStringCreateWithBytes(null, bytes.ptr, @intCast(bytes.len), 0x08000100, 0);
}
