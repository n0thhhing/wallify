const std = @import("std");

pub const Ref = ?*anyopaque;

pub const Point = extern struct { x: f64, y: f64 };
pub const Size = extern struct { width: f64, height: f64 };
pub const Rect = extern struct { origin: Point, size: Size };

pub extern "c" fn fopen(filename: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
pub extern "c" fn fprintf(stream: *anyopaque, format: [*:0]const u8, ...) c_int;
pub extern "c" fn fclose(stream: *anyopaque) c_int;

pub fn rect(x: f64, y: f64, w: f64, h: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}

pub const winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

pub const timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

pub const stat_t = extern struct {
    st_dev: i32,
    st_mode: u16,
    st_nlink: u16,
    st_ino: u64,
    st_uid: u32,
    st_gid: u32,
    st_rdev: i32,
    st_atimespec: timespec,
    st_mtimespec: timespec,
    st_ctimespec: timespec,
    st_birthtimespec: timespec,
    st_size: i64,
    st_blocks: i64,
    st_blksize: i32,
    st_flags: u32,
    st_gen: u32,
    st_lspare: i32,
    st_qspare: [2]i64,
};

pub extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
pub extern "c" fn clock_gettime(clk_id: c_int, tp: *timespec) c_int;
pub extern "c" fn stat(path: [*:0]const u8, buf: *stat_t) c_int;

pub const STDIN_FILENO: c_int = 0;
pub const TIOCGWINSZ: c_ulong = 0x40087468;
pub const CLOCK_MONOTONIC: c_int = 6;

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

// 1. Mutex & POSIX & Time Helpers
var render_mutex: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER;

// Kitty's panel is an NSWindow in this process.  Moving that window keeps the
// terminal, image surface, and playback state alive; recreating the panel does
// not.  Positions are stored as desktop-widget grid coordinates.
var panel_drag_window: Ref = null;
var panel_drag_mouse: Point = .{ .x = 0, .y = 0 };
var panel_drag_origin: Point = .{ .x = 0, .y = 0 };
var panel_drag_grid_x: i32 = 0;
var panel_drag_grid_y: i32 = 0;
const widget_grid_pitch: f64 = 180.0;

fn panelWindow() Ref {
    const app = send0(Ref, objc_getClass("NSApplication"), "sharedApplication");
    if (send0(Ref, app, "keyWindow")) |window| return window;
    if (send0(Ref, app, "mainWindow")) |window| return window;
    // A panel normally is the application's main window, but use the visible
    // window list as a fallback after an AppKit menu temporarily owns focus.
    const windows = send0(Ref, app, "windows");
    const count = send0(usize, windows, "count");
    for (0..count) |index| {
        const window = send1(Ref, windows, "objectAtIndex:", usize, index);
        if (send0(bool, window, "isVisible")) return window;
    }
    return null;
}

pub export fn widget_begin_panel_drag(grid_x: c_int, grid_y: c_int) callconv(.c) void {
    panel_drag_window = panelWindow();
    panel_drag_mouse = send0(Point, objc_getClass("NSEvent"), "mouseLocation");
    if (panel_drag_window) |window| panel_drag_origin = send0(Rect, window, "frame").origin;
    panel_drag_grid_x = @max(0, grid_x);
    panel_drag_grid_y = @max(0, grid_y);
}

pub export fn widget_update_panel_drag() callconv(.c) void {
    const window = panel_drag_window orelse return;
    const mouse = send0(Point, objc_getClass("NSEvent"), "mouseLocation");
    const dx = mouse.x - panel_drag_mouse.x;
    // AppKit's screen coordinates start at the bottom, while widget rows grow
    // down from the menu bar.
    const dy = panel_drag_mouse.y - mouse.y;
    const origin = Point{ .x = panel_drag_origin.x + dx, .y = panel_drag_origin.y - dy };
    send1(void, window, "setFrameOrigin:", Point, origin);
}

pub export fn widget_end_panel_drag() callconv(.c) void {
    if (panel_drag_window) |window| {
        const screen = send0(Ref, window, "screen");
        if (screen != null) {
            const visible = send0(Rect, screen, "visibleFrame");
            const frame = send0(Rect, window, "frame");
            panel_drag_grid_x = @max(0, @as(i32, @intFromFloat(@round((frame.origin.x - visible.origin.x - 14) / widget_grid_pitch))));
            panel_drag_grid_y = @max(0, @as(i32, @intFromFloat(@round((visible.origin.y + visible.size.height - 12 - frame.size.height - frame.origin.y) / widget_grid_pitch))));
            const snapped = Point{
                .x = visible.origin.x + 14 + @as(f64, @floatFromInt(panel_drag_grid_x)) * widget_grid_pitch,
                .y = visible.origin.y + visible.size.height - 12 - frame.size.height - @as(f64, @floatFromInt(panel_drag_grid_y)) * widget_grid_pitch,
            };
            send1(void, window, "setFrameOrigin:", Point, snapped);
        }
    }
    panel_drag_window = null;
}

pub export fn widget_panel_grid_x() callconv(.c) c_int {
    return panel_drag_grid_x;
}

pub export fn widget_panel_grid_y() callconv(.c) c_int {
    return panel_drag_grid_y;
}

pub export fn widget_render_lock() callconv(.c) void {
    _ = std.c.pthread_mutex_lock(&render_mutex);
}

pub export fn widget_render_unlock() callconv(.c) void {
    _ = std.c.pthread_mutex_unlock(&render_mutex);
}

pub export fn widget_terminal_columns() callconv(.c) c_int {
    var size: winsize = std.mem.zeroes(winsize);
    return if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) == 0) size.ws_col else 0;
}

pub export fn widget_terminal_rows() callconv(.c) c_int {
    var size: winsize = std.mem.zeroes(winsize);
    return if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) == 0) size.ws_row else 0;
}

pub export fn widget_scale_factor() callconv(.c) f64 {
    const screen = send0(Ref, objc_getClass("NSScreen"), "mainScreen") orelse return 1.0;
    return send0(f64, screen, "backingScaleFactor");
}

pub export fn widget_cell_width() callconv(.c) f64 {
    var size: winsize = std.mem.zeroes(winsize);
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) != 0 or size.ws_col == 0) return 0;
    return @as(f64, @floatFromInt(size.ws_xpixel)) / @as(f64, @floatFromInt(size.ws_col));
}

pub export fn widget_cell_height() callconv(.c) f64 {
    var size: winsize = std.mem.zeroes(winsize);
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) != 0 or size.ws_row == 0) return 0;
    return @as(f64, @floatFromInt(size.ws_ypixel)) / @as(f64, @floatFromInt(size.ws_row));
}

pub export fn widget_monotonic_time() callconv(.c) f64 {
    var now: timespec = undefined;
    _ = clock_gettime(CLOCK_MONOTONIC, &now);
    return @as(f64, @floatFromInt(now.tv_sec)) + @as(f64, @floatFromInt(now.tv_nsec)) / 1e9;
}

pub export fn widget_mouse_location() callconv(.c) Point {
    return send0(Point, objc_getClass("NSEvent"), "mouseLocation");
}

pub const PanelSnap = extern struct {
    found: bool = false,
    margin_left: i32 = 0,
    margin_top: i32 = 0,
    outline_x: f64 = 0,
    outline_y: f64 = 0,
    outline_width: f64 = 0,
    outline_height: f64 = 0,
};

var snap_outline: Ref = null;
var snap_outline_rect = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } };

extern "c" fn popen(command: [*c]const u8, type: [*c]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fflush(stream: *anyopaque) c_int;
var preview_pipe: ?*anyopaque = null;

fn updateSnapOutline(_: Ref) callconv(.c) void {
    if (preview_pipe == null) {
        preview_pipe = popen("./preview_frame", "w");
    }
    if (preview_pipe) |pipe| {
        _ = fprintf(pipe, "%f %f %f %f\n", snap_outline_rect.origin.x, snap_outline_rect.origin.y, snap_outline_rect.size.width, snap_outline_rect.size.height);
        _ = fflush(pipe);
    }
}

fn hideSnapOutline(_: Ref) callconv(.c) void {
    if (preview_pipe) |pipe| {
        _ = fprintf(pipe, "0 0 0 0\n");
        _ = fflush(pipe);
    }
}

pub export fn widget_show_snap_outline(x: f64, y: f64, width: f64, height: f64) callconv(.c) void {
    const file = fopen("/tmp/wallify.log", "a");
    if (file != null) {
        _ = fprintf(file.?, "SHOW SNAP OUTLINE CALLED: x=%f, y=%f, w=%f, h=%f\n", x, y, width, height);
        _ = fclose(file.?);
    }
    snap_outline_rect = rect(x, y, width, height);
    dispatch_async_f(dispatch_get_main_queue(), null, updateSnapOutline);
}

pub export fn widget_hide_snap_outline() callconv(.c) void {
    dispatch_async_f(dispatch_get_main_queue(), null, hideSnapOutline);
}

fn stringEquals(value: Ref, expected: []const u8) bool {
    if (value == null) return false;
    var buffer: [128]u8 = undefined;
    if (CFStringGetCString(value, &buffer, buffer.len, 0x08000100) == 0) return false;
    return std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), expected);
}

fn stringContains(value: Ref, needle: []const u8) bool {
    if (value == null) return false;
    var buffer: [128]u8 = undefined;
    if (CFStringGetCString(value, &buffer, buffer.len, 0x08000100) == 0) return false;
    return std.mem.indexOf(u8, std.mem.sliceTo(&buffer, 0), needle) != null;
}

fn stringHasText(value: Ref) bool {
    if (value == null) return false;
    return CFStringGetLength(value) > 0;
}

/// Return a magnetic drop target only when an on-screen widget edge is close.
/// The window list gives desktop-widget bounds in the same screen coordinate
/// space as Kitty's panel margins, so free placement remains possible between
/// unrelated widgets.
var cached_offset_x: f64 = 0;
var cached_offset_y: f64 = 36;
var has_cached_offsets: bool = false;

pub export fn widget_start_drag(margin_left: i32, margin_top: i32, visual_width: f64) callconv(.c) void {
    const list = CGWindowListCopyWindowInfo(1, 0) orelse return;
    defer CFRelease(list);
    const count = CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = CFArrayGetValueAtIndex(list, index);
        const bounds_dict = CFDictionaryGetValue(info, kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        if (stringEquals(CFDictionaryGetValue(info, kCGWindowName), "spotify-player")) {
            cached_offset_x = bounds.origin.x - @as(f64, @floatFromInt(margin_left));
            cached_offset_y = bounds.origin.y - @as(f64, @floatFromInt(margin_top));
            has_cached_offsets = true;
            return;
        }
        const owner = CFDictionaryGetValue(info, kCGWindowOwnerName);
        if (stringContains(owner, "kitty") and
            bounds.size.width >= visual_width * 0.7 and bounds.size.width <= visual_width * 5.0)
        {
            cached_offset_x = bounds.origin.x - @as(f64, @floatFromInt(margin_left));
            cached_offset_y = bounds.origin.y - @as(f64, @floatFromInt(margin_top));
            has_cached_offsets = true;
            return;
        }
    }
}

pub export fn widget_nearby_panel_snap(margin_left: i32, margin_top: i32, visual_left: f64, visual_top: f64, visual_width: f64, visual_height: f64) callconv(.c) PanelSnap {
    const list = CGWindowListCopyWindowInfo(1, 0) orelse return .{};
    defer CFRelease(list);

    var candidates: [64]Rect = undefined;
    var candidate_count: usize = 0;
    const count = CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = CFArrayGetValueAtIndex(list, index);
        const bounds_dict = CFDictionaryGetValue(info, kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        const owner = CFDictionaryGetValue(info, kCGWindowOwnerName);
        if (!stringEquals(owner, "Notification Center")) continue;
        const layer_ref = CFDictionaryGetValue(info, kCGWindowLayer);
        var layer: i32 = 0;
        if (layer_ref == null or !CFNumberGetValue(layer_ref, 3, &layer)) continue;
        if (layer != -2147483601) continue;
        if (bounds.size.width < 80 or bounds.size.height < 80 or bounds.size.width > 600 or bounds.size.height > 400) continue;
        if (candidate_count < candidates.len) {
            candidates[candidate_count] = bounds;
            candidate_count += 1;
        }
    }

    const align_adj_x: f64 = 3.0;
    const align_adj_y: f64 = 3.0;

    const offset_x = if (has_cached_offsets) cached_offset_x else 0;
    const offset_y = if (has_cached_offsets) cached_offset_y else 31;
    const visual_x = offset_x + @as(f64, @floatFromInt(margin_left)) + visual_left - align_adj_x;
    const visual_y = offset_y + @as(f64, @floatFromInt(margin_top)) + visual_top - align_adj_y;

    const gap: f64 = 0.0;
    const threshold_sq: f64 = 120.0 * 120.0; 
    var best_dist = threshold_sq;
    var result = PanelSnap{};

    for (candidates[0..candidate_count]) |neighbor| {
        const targets = [_]Point{
            .{ .x = neighbor.origin.x + neighbor.size.width + gap, .y = neighbor.origin.y },
            .{ .x = neighbor.origin.x - visual_width - gap, .y = neighbor.origin.y },
            .{ .x = neighbor.origin.x, .y = neighbor.origin.y + neighbor.size.height + gap },
            .{ .x = neighbor.origin.x, .y = neighbor.origin.y - visual_height - gap },
            // Corner snapping targets for diagonal alignment
            .{ .x = neighbor.origin.x + neighbor.size.width + gap, .y = neighbor.origin.y + neighbor.size.height + gap },
            .{ .x = neighbor.origin.x - visual_width - gap, .y = neighbor.origin.y - visual_height - gap },
            .{ .x = neighbor.origin.x + neighbor.size.width + gap, .y = neighbor.origin.y - visual_height - gap },
            .{ .x = neighbor.origin.x - visual_width - gap, .y = neighbor.origin.y + neighbor.size.height + gap },
            // Support snapping above/below column 2 of a 2-column neighbor
            .{ .x = neighbor.origin.x + 180.0, .y = neighbor.origin.y + neighbor.size.height + gap },
            .{ .x = neighbor.origin.x + 180.0, .y = neighbor.origin.y - visual_height - gap },
        };
        for (targets) |t| {
            const dx = t.x - visual_x;
            const dy = t.y - visual_y;
            const dist_sq = dx * dx + dy * dy;
            if (dist_sq < best_dist) {
                best_dist = dist_sq;
                result = .{
                    .found = true,
                    .margin_left = @as(i32, @intFromFloat(@round(t.x - offset_x - visual_left + align_adj_x))),
                    .margin_top = @as(i32, @intFromFloat(@round(t.y - offset_y - visual_top + align_adj_y))),
                    .outline_x = t.x + 8.0,
                    .outline_y = t.y + 8.0,
                    .outline_width = if (visual_width > 200) 344.0 else 164.0,
                    .outline_height = 164.0,
                };
            }
        }
    }
    return result;
}

// 2. Text rendering
pub export fn widget_text_width(utf8: [*]const u8, length: usize, font_size: f64, bold: c_int) callconv(.c) f64 {
    if (length == 0) return 0;
    const str = CFStringCreateWithBytes(null, utf8, @intCast(length), 0x08000100, 0);
    if (str == null) return 0;
    defer CFRelease(str);
    const font = CTFontCreateUIFontForLanguage(if (bold != 0) kCTFontUIFontEmphasizedSystem else kCTFontUIFontSystem, font_size, null);
    if (font == null) return 0;
    defer CFRelease(font);
    const keys = [_]Ref{kCTFontAttributeName};
    const values = [_]Ref{font};
    const attrs = CFDictionaryCreate(null, &keys, &values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    defer CFRelease(attrs);
    const attr = CFAttributedStringCreate(null, str, attrs);
    defer CFRelease(attr);
    const line = CTLineCreateWithAttributedString(attr);
    defer CFRelease(line);
    return CTLineGetTypographicBounds(line, null, null, null);
}

pub export fn widget_text(pixels: [*]u32, width: usize, height: usize, utf8: [*]const u8, length: usize, x: f64, y: f64, max_width: f64, font_size: f64, bold: c_int, right_align: c_int, r: u8, g: u8, b: u8) callconv(.c) void {
    if (length == 0 or max_width <= 0) return;
    const str = CFStringCreateWithBytes(null, utf8, @intCast(length), 0x08000100, 0);
    if (str == null) return;
    defer CFRelease(str);

    const font = CTFontCreateUIFontForLanguage(if (bold != 0) kCTFontUIFontEmphasizedSystem else kCTFontUIFontSystem, font_size, null);
    if (font == null) return;
    defer CFRelease(font);

    const space = CGColorSpaceCreateDeviceRGB();
    defer CGColorSpaceRelease(space);

    const components = [_]f64{ @as(f64, @floatFromInt(r)) / 255.0, @as(f64, @floatFromInt(g)) / 255.0, @as(f64, @floatFromInt(b)) / 255.0, 1.0 };
    const color = CGColorCreate(space, &components);
    defer CGColorRelease(color);

    const keys = [_]Ref{ kCTFontAttributeName, kCTForegroundColorAttributeName };
    const values = [_]Ref{ font, color };
    const attrs = CFDictionaryCreate(null, &keys, &values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    defer CFRelease(attrs);

    const attr = CFAttributedStringCreate(null, str, attrs);
    defer CFRelease(attr);

    var line = CTLineCreateWithAttributedString(attr);

    if (CTLineGetTypographicBounds(line, null, null, null) > max_width) {
        const dots = string("…");
        defer CFRelease(dots);
        const token_attr = CFAttributedStringCreate(null, dots, attrs);
        defer CFRelease(token_attr);
        const token = CTLineCreateWithAttributedString(token_attr);
        defer CFRelease(token);
        const truncated = CTLineCreateTruncatedLine(line, max_width, kCTLineTruncationEnd, token);
        if (truncated != null) {
            CFRelease(line);
            line = truncated;
        }
    }
    defer CFRelease(line);

    const context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (context != null) {
        defer CGContextRelease(context);
        var ascent: f64 = 0;
        const line_width = CTLineGetTypographicBounds(line, &ascent, null, null);
        CGContextClipToRect(context, rect(x, 0, max_width, @floatFromInt(height)));
        CGContextSetShouldAntialias(context, true);
        const text_x = x + if (right_align != 0) max_width - line_width else 0;
        const text_y = @as(f64, @floatFromInt(height)) - y - ascent;
        CGContextSetTextPosition(context, text_x, text_y);
        CTLineDraw(line, context);
    }
}

// Same Core Text renderer, but with a fixed viewport and no ellipsis. This is
// used by the compact player title so it can move smoothly behind a mask.
pub export fn widget_text_clipped(pixels: [*]u32, width: usize, height: usize, utf8: [*]const u8, length: usize, x: f64, y: f64, clip_x: f64, clip_width: f64, font_size: f64, bold: c_int, r: u8, g: u8, b: u8) callconv(.c) void {
    if (length == 0 or clip_width <= 0) return;
    const str = CFStringCreateWithBytes(null, utf8, @intCast(length), 0x08000100, 0);
    if (str == null) return;
    defer CFRelease(str);
    const font = CTFontCreateUIFontForLanguage(if (bold != 0) kCTFontUIFontEmphasizedSystem else kCTFontUIFontSystem, font_size, null);
    if (font == null) return;
    defer CFRelease(font);
    const space = CGColorSpaceCreateDeviceRGB();
    defer CGColorSpaceRelease(space);
    const components = [_]f64{ @as(f64, @floatFromInt(r)) / 255.0, @as(f64, @floatFromInt(g)) / 255.0, @as(f64, @floatFromInt(b)) / 255.0, 1.0 };
    const color = CGColorCreate(space, &components);
    defer CGColorRelease(color);
    const keys = [_]Ref{ kCTFontAttributeName, kCTForegroundColorAttributeName };
    const values = [_]Ref{ font, color };
    const attrs = CFDictionaryCreate(null, &keys, &values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    defer CFRelease(attrs);
    const attr = CFAttributedStringCreate(null, str, attrs);
    defer CFRelease(attr);
    const line = CTLineCreateWithAttributedString(attr);
    defer CFRelease(line);
    const context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (context == null) return;
    defer CGContextRelease(context);
    var ascent: f64 = 0;
    _ = CTLineGetTypographicBounds(line, &ascent, null, null);
    CGContextClipToRect(context, rect(clip_x, 0, clip_width, @floatFromInt(height)));
    CGContextSetShouldAntialias(context, true);
    CGContextSetTextPosition(context, x, @as(f64, @floatFromInt(height)) - y - ascent);
    CTLineDraw(line, context);
}

// 3. Icons and SF Symbols
var symbol_images: [4]Ref = .{ null, null, null, null };
var symbol_sizes: [4]Size = .{ .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 }, .{ .width = 0, .height = 0 } };
var symbol_once: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn initSymbols() void {
    const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer send0(void, pool, "release");

    const names = [_][]const u8{ "play.fill", "pause.fill", "backward.fill", "forward.fill" };
    const img_cls = objc_getClass("NSImage");
    const cfg_cls = objc_getClass("NSImageSymbolConfiguration");

    for (names, 0..) |name, i| {
        const pt_size: f64 = if (i < 2) 28.0 else 17.0;

        const name_str = string(name);
        defer CFRelease(name_str);
        var img = send2(Ref, img_cls, "imageWithSystemSymbolName:accessibilityDescription:", Ref, name_str, Ref, null);
        if (img == null) continue;

        const cfg = send2(Ref, cfg_cls, "configurationWithPointSize:weight:", f64, pt_size, f64, 0.0);
        img = send1(Ref, img, "imageWithSymbolConfiguration:", Ref, cfg);
        if (img == null) continue;

        const sz = send0(Size, img, "size");
        const raster_sz = Size{ .width = sz.width * 3, .height = sz.height * 3 };

        const raster = send1(Ref, send0(Ref, img_cls, "alloc"), "initWithSize:", Size, raster_sz);
        send0(void, raster, "lockFocus");
        send4(void, img, "drawInRect:fromRect:operation:fraction:", Rect, rect(0, 0, raster_sz.width, raster_sz.height), Rect, rect(0, 0, 0, 0), usize, 2, f64, 1.0);
        send0(void, raster, "unlockFocus");

        const cg = send3(Ref, raster, "CGImageForProposedRect:context:hints:", ?*Rect, null, Ref, null, Ref, null);
        if (cg != null) {
            symbol_images[i] = CGImageRetain(cg);
            symbol_sizes[i] = sz;
        }
    }
}

pub export fn widget_draw_symbol(context: Ref, kind: c_int) callconv(.c) c_int {
    if (!symbol_once.swap(true, .monotonic)) {
        initSymbols();
    }
    if (kind < 0 or kind > 3 or symbol_images[@intCast(kind)] == null) return 0;
    const idx: usize = @intCast(kind);
    const sz = symbol_sizes[idx];
    const r = rect(-sz.width / 2.0, -sz.height / 2.0, sz.width, sz.height);
    CGContextSaveGState(context);
    CGContextClipToMask(context, r, symbol_images[idx]);
    CGContextFillRect(context, r);
    CGContextRestoreGState(context);
    return 1;
}

fn rounded_triangle(context: Ref, x: f64, y: f64, w: f64, h: f64) void {
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, x, y - h / 2.0);
    CGContextAddLineToPoint(context, x + w, y);
    CGContextAddLineToPoint(context, x, y + h / 2.0);
    CGContextClosePath(context);
    CGContextDrawPath(context, kCGPathFillStroke);
}

pub export fn widget_icon(pixels: [*]u32, width: usize, height: usize, x: f64, y: f64, kind: c_int, hover: f64, opacity: f64, scale: f64) callconv(.c) void {
    _ = hover;
    const space = CGColorSpaceCreateDeviceRGB();
    const c = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (c == null) return;
    defer CGContextRelease(c);

    CGContextTranslateCTM(c, x, @as(f64, @floatFromInt(height)) - y);
    CGContextScaleCTM(c, scale, scale);
    CGContextSetAlpha(c, opacity);
    CGContextBeginTransparencyLayer(c, null);
    defer CGContextEndTransparencyLayer(c);

    const color: f64 = 0.83;
    CGContextSetRGBFillColor(c, color, color, color, 1.0);
    CGContextSetRGBStrokeColor(c, color, color, color, 1.0);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextSetLineWidth(c, 1.6);

    if (widget_draw_symbol(c, kind) != 0) {
        // Native symbol drawn
    } else if (kind == 0) {
        rounded_triangle(c, -7, 0, 18, 23);
    } else if (kind == 1) {
        const left = CGPathCreateWithRoundedRect(rect(-8, -12, 6, 24), 1.8, 1.8, null);
        const right = CGPathCreateWithRoundedRect(rect(2, -12, 6, 24), 1.8, 1.8, null);
        CGContextAddPath(c, left);
        CGContextAddPath(c, right);
        CGContextFillPath(c);
        CGPathRelease(left);
        CGPathRelease(right);
    } else {
        if (kind == 2) CGContextScaleCTM(c, -1, 1);
        rounded_triangle(c, -8, 0, 9, 12);
        rounded_triangle(c, 2, 0, 9, 12);
    }
}

// 4. Artwork Glow
const W: usize = 320;
const H: usize = 220;

var glow_current: Ref = null;
var glow_previous: Ref = null;
var glow_modified: timespec = .{ .tv_sec = 0, .tv_nsec = 0 };
var glow_changed_at: f64 = 0;
var float_buf: [320 * 220 * 4]f32 = undefined;

fn makeGlow() Ref {
    const path = "/tmp/art.bmp";
    const url = CFURLCreateFromFileSystemRepresentation(null, path.ptr, path.len, 0);
    if (url == null) return null;
    defer CFRelease(url);

    const source = CGImageSourceCreateWithURL(url, null);
    if (source == null) return null;
    defer CFRelease(source);

    const art = CGImageSourceCreateImageAtIndex(source, 0, null);
    if (art == null) return null;
    defer CGImageRelease(art);

    const space = CGColorSpaceCreateDeviceRGB();
    const bitmap = CGBitmapContextCreate(null, W, H, 8, W * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (bitmap == null) return null;
    defer CGContextRelease(bitmap);

    CGContextScaleCTM(bitmap, 0.5, 0.5);
    CGContextTranslateCTM(bitmap, 220, 220);
    CGContextRotateCTM(bitmap, -92.0 * std.math.pi / 180.0);
    CGContextScaleCTM(bitmap, 1.3, 1.4);
    CGContextSaveGState(bitmap);
    const art_clip = CGPathCreateWithRoundedRect(rect(-76, -76, 152, 152), 14, 14, null);
    CGContextAddPath(bitmap, art_clip);
    CGContextClip(bitmap);
    CGPathRelease(art_clip);
    CGContextDrawImage(bitmap, rect(-76, -76, 152, 152), art);
    CGContextRestoreGState(bitmap);

    const data: [*]u8 = @ptrCast(CGBitmapContextGetData(bitmap) orelse return null);

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

    return CGBitmapContextCreateImage(bitmap);
}

pub export fn widget_artwork_glow(pixels: [*]u32, w: usize, h: usize, card_width: f64, card_height: f64, scale: f64, opacity: f64, now: f64, animations: c_int) callconv(.c) void {
    var info: stat_t = undefined;
    if (stat("/tmp/art.bmp", &info) == 0 and (glow_current == null or info.st_mtimespec.tv_sec != glow_modified.tv_sec or info.st_mtimespec.tv_nsec != glow_modified.tv_nsec)) {
        const next = makeGlow();
        if (next != null) {
            if (glow_previous != null) CGImageRelease(glow_previous);
            glow_previous = glow_current;
            glow_current = next;
            glow_modified = info.st_mtimespec;
            glow_changed_at = now;
        }
    }

    if (glow_current == null or opacity <= 0) return;

    const space = CGColorSpaceCreateDeviceRGB();
    const ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (ctx == null) return;
    defer CGContextRelease(ctx);

    const fh: f64 = @floatFromInt(h);
    CGContextTranslateCTM(ctx, 0, fh);
    CGContextScaleCTM(ctx, scale, -scale);

    const clip = CGPathCreateWithRoundedRect(rect(0, 0, card_width, card_height), 26, 26, null);
    CGContextAddPath(ctx, clip);
    CGContextClip(ctx);
    CGPathRelease(clip);

    var progress: f64 = if (animations != 0) (now - glow_changed_at) / 0.5 else 1.0;
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
    const t = progress * progress * progress * (10.0 + progress * (-15.0 + 6.0 * progress));

    CGContextSetAlpha(ctx, opacity * 0.5);
    CGContextBeginTransparencyLayer(ctx, null);
    defer CGContextEndTransparencyLayer(ctx);

    CGContextSetBlendMode(ctx, kCGBlendModePlusLighter);
    CGContextTranslateCTM(ctx, 0, 200);
    CGContextScaleCTM(ctx, 1, -1);

    if (glow_previous != null and t < 1.0) {
        CGContextSetAlpha(ctx, 1.0 - t);
        CGContextDrawImage(ctx, rect(-120, -120, 640, 440), glow_previous);
    }
    CGContextSetAlpha(ctx, if (glow_previous != null) t else 1.0);
    CGContextDrawImage(ctx, rect(-120, -120, 640, 440), glow_current);
}

// 5. Spotify & Application & Context Menu
var pending_state: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(-1);

fn spotifyCallback(_: Ref, _: Ref, _: Ref, _: Ref, _: Ref) callconv(.c) void {
    pending_state.store(1, .monotonic);
}

pub export fn widget_spotify_observe() callconv(.c) void {
    const center = CFNotificationCenterGetDistributedCenter();
    const name = string("com.spotify.client.PlaybackStateChanged");
    defer CFRelease(name);
    CFNotificationCenterAddObserver(center, null, spotifyCallback, name, null, 0);
}

pub export fn widget_spotify_take_state() callconv(.c) c_int {
    return pending_state.swap(-1, .monotonic);
}

pub export fn widget_open_spotify() callconv(.c) void {
    const main_q = dispatch_get_main_queue();
    const Work = struct {
        fn run(_: Ref) callconv(.c) void {
            const url_str = string("spotify:");
            defer CFRelease(url_str);
            const url = send1(Ref, objc_getClass("NSURL"), "URLWithString:", Ref, url_str);
            const ws = send0(Ref, objc_getClass("NSWorkspace"), "sharedWorkspace");
            _ = send1(bool, ws, "openURL:", Ref, url);
        }
    };
    dispatch_async_f(main_q, null, Work.run);
}

var menu_action: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(0);
var menu_open: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn chooseCallback(_: Ref, _: Ref, sender: Ref) callconv(.c) void {
    const tag = send0(isize, sender, "tag");
    menu_action.store(@intCast(tag), .monotonic);
}

fn getMenuTarget() Ref {
    const TargetHolder = struct {
        var instance: Ref = null;
        var once: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
        fn get() Ref {
            if (!once.swap(true, .monotonic)) {
                const superclass = objc_getClass("NSObject");
                const cls = objc_allocateClassPair(superclass, "WallifyMenuTarget", 0);
                if (cls != null) {
                    _ = class_addMethod(cls, sel_registerName("choose:"), @ptrCast(&chooseCallback), "v@:@");
                    objc_registerClassPair(cls);
                    instance = send0(Ref, send0(Ref, cls, "alloc"), "init");
                }
            }
            return instance;
        }
    };
    return TargetHolder.get();
}

pub export fn widget_application_init() callconv(.c) void {
    const app = send0(Ref, objc_getClass("NSApplication"), "sharedApplication");
    // NSApplicationActivationPolicyAccessory = 1
    _ = send1(bool, app, "setActivationPolicy:", isize, 1);
}

pub export fn widget_application_run() callconv(.c) void {
    const app = send0(Ref, objc_getClass("NSApplication"), "sharedApplication");
    send0(void, app, "run");
}

pub export fn widget_context_menu_action() callconv(.c) c_int {
    return menu_action.swap(0, .monotonic);
}

const ContextMenuCtx = struct {
    playing: c_int,
    glow: c_int,
    animations: c_int,
    dim: c_int,
    frame: c_int,
    intensity: c_int,
    speed: c_int,
    source: c_int,
    mode: c_int,

    fn show(ctx_ptr: Ref) callconv(.c) void {
        const self: *ContextMenuCtx = @ptrCast(@alignCast(ctx_ptr));
        defer std.heap.c_allocator.destroy(self);

        const ns_app = send0(Ref, objc_getClass("NSApplication"), "sharedApplication");
        const ns_ws = send0(Ref, objc_getClass("NSWorkspace"), "sharedWorkspace");
        const previous_app = send0(Ref, ns_ws, "frontmostApplication");
        const location = send0(Point, objc_getClass("NSEvent"), "mouseLocation");

        _ = send1(bool, ns_app, "activateIgnoringOtherApps:", bool, true);

        const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
        defer send0(void, pool, "release");

        const target = getMenuTarget();
        const menu_cls = objc_getClass("NSMenu");
        const item_cls = objc_getClass("NSMenuItem");

        const title_str = string("Wallify");
        defer CFRelease(title_str);
        const menu = send1(Ref, send0(Ref, menu_cls, "alloc"), "initWithTitle:", Ref, title_str);
        send1(void, menu, "setAutoenablesItems:", bool, false);

        const empty_str = string("");
        defer CFRelease(empty_str);

        const main_labels = [_][]const u8{
            if (self.playing != 0) "Pause" else "Play",
            "Previous Track",
            "Next Track",
            "Open Spotify",
        };

        const choose_sel = sel_registerName("choose:");

        for (main_labels, 0..) |lbl, i| {
            const s = string(lbl);
            defer CFRelease(s);
            const item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, s, Ref, choose_sel, Ref, empty_str);
            send1(void, item, "setTarget:", Ref, target);
            send1(void, item, "setTag:", isize, @intCast(i + 1));
            send1(void, menu, "addItem:", Ref, item);
        }

        send1(void, menu, "addItem:", Ref, send0(Ref, item_cls, "separatorItem"));

        const source_title = string("Media Source");
        defer CFRelease(source_title);
        const source_item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, source_title, Ref, null, Ref, empty_str);
        const source_submenu = send1(Ref, send0(Ref, menu_cls, "alloc"), "initWithTitle:", Ref, source_title);
        send1(void, source_submenu, "setAutoenablesItems:", bool, false);

        const sources = [_][]const u8{ "Now Playing", "Spotify" };
        for (sources, 0..) |src_name, i| {
            const s = string(src_name);
            defer CFRelease(s);
            const item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, s, Ref, choose_sel, Ref, empty_str);
            send1(void, item, "setTarget:", Ref, target);
            send1(void, item, "setTag:", isize, @intCast(50 + i));
            send1(void, item, "setState:", isize, if (self.source == i) 1 else 0);
            send1(void, source_submenu, "addItem:", Ref, item);
        }
        send1(void, source_item, "setSubmenu:", Ref, source_submenu);
        send1(void, menu, "addItem:", Ref, source_item);

        const mode_title = string("Widget Mode");
        defer CFRelease(mode_title);
        const mode_item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, mode_title, Ref, null, Ref, empty_str);
        const mode_submenu = send1(Ref, send0(Ref, menu_cls, "alloc"), "initWithTitle:", Ref, mode_title);
        send1(void, mode_submenu, "setAutoenablesItems:", bool, false);
        const modes = [_][]const u8{ "Compact", "Expanded" };
        for (modes, 0..) |mode_name, i| {
            const mode_str = string(mode_name);
            defer CFRelease(mode_str);
            const item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, mode_str, Ref, choose_sel, Ref, empty_str);
            send1(void, item, "setTarget:", Ref, target);
            send1(void, item, "setTag:", isize, @intCast(60 + i));
            send1(void, item, "setState:", isize, if (self.mode == i) 1 else 0);
            send1(void, mode_submenu, "addItem:", Ref, item);
        }
        send1(void, mode_item, "setSubmenu:", Ref, mode_submenu);
        send1(void, menu, "addItem:", Ref, mode_item);

        send1(void, menu, "addItem:", Ref, send0(Ref, item_cls, "separatorItem"));

        const set_title = string("Widget Settings");
        defer CFRelease(set_title);
        const settings_item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, set_title, Ref, null, Ref, empty_str);
        const submenu = send1(Ref, send0(Ref, menu_cls, "alloc"), "initWithTitle:", Ref, set_title);
        send1(void, submenu, "setAutoenablesItems:", bool, false);

        const prefs = [_][]const u8{ "Artwork Glow", "Animations", "Dim Artwork When Paused" };
        const enabled = [_]c_int{ self.glow, self.animations, self.dim };

        for (prefs, 0..) |p_name, i| {
            const s = string(p_name);
            defer CFRelease(s);
            const item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, s, Ref, choose_sel, Ref, empty_str);
            send1(void, item, "setTarget:", Ref, target);
            send1(void, item, "setTag:", isize, @intCast(i + 5));
            send1(void, item, "setState:", isize, if (enabled[i] != 0) 1 else 0);
            send1(void, submenu, "addItem:", Ref, item);
        }

        send1(void, submenu, "addItem:", Ref, send0(Ref, item_cls, "separatorItem"));

        const groups = [_][]const u8{ "Frame Strength", "Glow Intensity", "Animation Speed" };
        const choices = [_][3][]const u8{
            .{ "Off", "Subtle", "Strong" },
            .{ "Low", "Normal", "High" },
            .{ "Slow", "Normal", "Fast" },
        };
        const selected = [_]c_int{ self.frame, self.intensity, self.speed };

        for (groups, 0..) |grp, g| {
            const grp_str = string(grp);
            defer CFRelease(grp_str);
            const parent_item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, grp_str, Ref, null, Ref, empty_str);
            const options_menu = send1(Ref, send0(Ref, menu_cls, "alloc"), "initWithTitle:", Ref, grp_str);
            send1(void, options_menu, "setAutoenablesItems:", bool, false);

            for (choices[g], 0..) |opt_name, o| {
                const opt_str = string(opt_name);
                defer CFRelease(opt_str);
                const item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, opt_str, Ref, choose_sel, Ref, empty_str);
                send1(void, item, "setTarget:", Ref, target);
                send1(void, item, "setTag:", isize, @intCast((g + 1) * 10 + o));
                send1(void, item, "setState:", isize, if (selected[g] == o) 1 else 0);
                send1(void, options_menu, "addItem:", Ref, item);
            }

            send1(void, parent_item, "setSubmenu:", Ref, options_menu);
            send1(void, submenu, "addItem:", Ref, parent_item);
        }

        send1(void, submenu, "addItem:", Ref, send0(Ref, item_cls, "separatorItem"));

        const reset_str = string("Restore Defaults");
        defer CFRelease(reset_str);
        const reset_item = send3(Ref, send0(Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", Ref, reset_str, Ref, choose_sel, Ref, empty_str);
        send1(void, reset_item, "setTarget:", Ref, target);
        send1(void, reset_item, "setTag:", isize, 40);
        send1(void, submenu, "addItem:", Ref, reset_item);

        send1(void, settings_item, "setSubmenu:", Ref, submenu);
        send1(void, menu, "addItem:", Ref, settings_item);

        _ = send3(bool, menu, "popUpMenuPositioningItem:atLocation:inView:", Ref, null, Point, location, Ref, null);

        if (previous_app != null) {
            const proc_info = send0(Ref, objc_getClass("NSProcessInfo"), "processInfo");
            const my_pid = send0(i32, proc_info, "processIdentifier");
            const prev_pid = send0(i32, previous_app, "processIdentifier");
            if (prev_pid != my_pid) {
                _ = send1(bool, previous_app, "activateWithOptions:", usize, 0);
            }
        }
        menu_open.store(false, .monotonic);
    }
};

pub export fn widget_context_menu(playing: c_int, glow: c_int, animations: c_int, dim: c_int, frame: c_int, intensity: c_int, speed: c_int, source: c_int, mode: c_int) callconv(.c) void {
    if (menu_open.swap(true, .monotonic)) return;
    const ctx = std.heap.c_allocator.create(ContextMenuCtx) catch {
        menu_open.store(false, .monotonic);
        return;
    };
    ctx.* = .{
        .playing = playing,
        .glow = glow,
        .animations = animations,
        .dim = dim,
        .frame = frame,
        .intensity = intensity,
        .speed = speed,
        .source = source,
        .mode = mode,
    };
    dispatch_async_f(dispatch_get_main_queue(), ctx, ContextMenuCtx.show);
}

pub export fn widget_is_spotify_running() callconv(.c) c_int {
    const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer send0(void, pool, "release");

    const bundle_id = string("com.spotify.client");
    defer CFRelease(bundle_id);

    const apps = send1(Ref, objc_getClass("NSRunningApplication"), "runningApplicationsWithBundleIdentifier:", Ref, bundle_id);
    if (apps == null) return 0;
    const count = send0(usize, apps, "count");
    return if (count > 0) 1 else 0;
}

pub export fn widget_spotify_control(cmd: c_int) callconv(.c) void {
    const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer send0(void, pool, "release");

    const script_text: []const u8 = switch (cmd) {
        0 => "if application \"Spotify\" is running then\ntell application \"Spotify\" to play\nelse\ntell application \"Spotify\" to activate\nend if",
        1 => "if application \"Spotify\" is running then tell application \"Spotify\" to pause",
        2 => "if application \"Spotify\" is running then\ntell application \"Spotify\" to playpause\nelse\ntell application \"Spotify\" to activate\nend if",
        3 => "if application \"Spotify\" is running then tell application \"Spotify\" to previous track",
        4 => "if application \"Spotify\" is running then tell application \"Spotify\" to next track",
        else => return,
    };

    const str = string(script_text);
    defer CFRelease(str);

    const script = send1(Ref, send0(Ref, objc_getClass("NSAppleScript"), "alloc"), "initWithSource:", Ref, str);
    if (script != null) {
        defer send0(void, script, "release");
        _ = send1(Ref, script, "executeAndReturnError:", ?*Ref, null);
    }
}

pub export fn widget_spotify_seek(position: f64) callconv(.c) void {
    const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer send0(void, pool, "release");

    var buf: [128]u8 = undefined;
    const script_fmt = std.fmt.bufPrintZ(&buf, "tell application \"Spotify\" to set player position to {d:.2}", .{position}) catch return;

    const str = string(script_fmt);
    defer CFRelease(str);

    const script = send1(Ref, send0(Ref, objc_getClass("NSAppleScript"), "alloc"), "initWithSource:", Ref, str);
    if (script != null) {
        defer send0(void, script, "release");
        _ = send1(Ref, script, "executeAndReturnError:", ?*Ref, null);
    }
}

pub export fn widget_query_spotify(buf: [*]u8, max_len: usize) callconv(.c) usize {
    const pool = send0(Ref, send0(Ref, objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer send0(void, pool, "release");

    const script_text =
        \\if application "Spotify" is running then
        \\  tell application "Spotify"
        \\      try
        \\          set tName to name of current track
        \\          set tArtist to artist of current track
        \\          set tState to player state as string
        \\          set tPos to player position as string
        \\          set tDur to ((duration of current track) / 1000.0) as string
        \\          set tArt to artwork url of current track
        \\          return tName & "|||" & tArtist & "|||" & tState & "|||" & tPos & "|||" & tDur & "|||" & tArt
        \\      on error
        \\          return "NO_TRACK"
        \\      end try
        \\  end tell
        \\else
        \\  return "CLOSED"
        \\end if
    ;

    const str = string(script_text);
    if (str == null) return 0;
    defer CFRelease(str);

    const script_cls = objc_getClass("NSAppleScript");
    const script = send1(Ref, send0(Ref, script_cls, "alloc"), "initWithSource:", Ref, str);
    if (script == null) return 0;
    defer send0(void, script, "release");

    const desc = send1(Ref, script, "executeAndReturnError:", ?*Ref, null);
    if (desc == null) return 0;

    const str_val = send0(Ref, desc, "stringValue");
    if (str_val == null) return 0;

    const len = CFStringGetLength(str_val);
    if (len <= 0) return 0;

    var cstr_buf: [1024]u8 = undefined;
    if (CFStringGetCString(str_val, &cstr_buf, cstr_buf.len, 0x08000100) == 0) return 0;

    const slice = std.mem.sliceTo(&cstr_buf, 0);
    const copy_len = @min(slice.len, max_len);
    @memcpy(buf[0..copy_len], slice[0..copy_len]);
    return copy_len;
}
