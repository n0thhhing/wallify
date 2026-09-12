const std = @import("std");
const macos = @import("../platform/macos.zig");

const Ref = macos.Ref;
const Point = macos.Point;
const Rect = macos.Rect;
const rect = macos.rect;
const send0 = macos.send0;
const send1 = macos.send1;
const send2 = macos.send2;
const send4 = macos.send4;
const string = macos.string;
const objc_getClass = macos.objc_getClass;
const dispatch_async_f = macos.dispatch_async_f;
const dispatch_get_main_queue = macos.dispatch_get_main_queue;
const CFRelease = macos.CFRelease;
const CFArrayGetCount = macos.CFArrayGetCount;
const CFArrayGetValueAtIndex = macos.CFArrayGetValueAtIndex;
const CFDictionaryGetValue = macos.CFDictionaryGetValue;
const CFNumberGetValue = macos.CFNumberGetValue;
const CFStringGetCString = macos.CFStringGetCString;
const CFStringGetLength = macos.CFStringGetLength;
const CGWindowListCopyWindowInfo = macos.CGWindowListCopyWindowInfo;
const CGRectMakeWithDictionaryRepresentation = macos.CGRectMakeWithDictionaryRepresentation;

// 1. Mutex & POSIX & Time Helpers
var render_mutex: std.atomic.Mutex = .unlocked;

// Kitty's panel is an NSWindow in this process. Moving that window keeps the
// terminal, image surface, and playback state alive; recreating the panel does
// not. Positions are stored as desktop-widget grid coordinates.
var panel_drag_window: Ref = null;
var panel_drag_mouse: Point = .{ .x = 0, .y = 0 };
var panel_drag_origin: Point = .{ .x = 0, .y = 0 };
var panel_drag_grid_x: i32 = 0;
var panel_drag_grid_y: i32 = 0;
const widget_grid_pitch: f64 = 180.0;

fn panelWindow() Ref {
    const app = send0(Ref, objc_getClass("NSApplication"), "sharedApplication");
    // The persistent debug and snap-preview panels belong to this same
    // process. Never let either become the draggable Kitty panel.
    const windows = send0(Ref, app, "windows");
    const count = send0(usize, windows, "count");
    for (0..count) |index| {
        const window = send1(Ref, windows, "objectAtIndex:", usize, index);
        if (send0(bool, window, "isVisible") and stringEquals(send0(Ref, window, "title"), "spotify-player")) return window;
    }
    if (send0(Ref, app, "keyWindow")) |window| if (window != snap_debug_panel and window != snap_outline) return window;
    if (send0(Ref, app, "mainWindow")) |window| if (window != snap_debug_panel and window != snap_outline) return window;
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
    while (!render_mutex.tryLock()) std.Thread.yield() catch {};
}

pub export fn widget_render_unlock() callconv(.c) void {
    render_mutex.unlock();
}

pub export fn widget_terminal_columns() callconv(.c) c_int {
    var size: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
    return if (std.posix.system.ioctl(std.posix.STDIN_FILENO, std.posix.T.IOCGWINSZ, &size) == 0) size.col else 0;
}

pub export fn widget_terminal_rows() callconv(.c) c_int {
    var size: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
    return if (std.posix.system.ioctl(std.posix.STDIN_FILENO, std.posix.T.IOCGWINSZ, &size) == 0) size.row else 0;
}

pub export fn widget_scale_factor() callconv(.c) f64 {
    const screen = send0(Ref, objc_getClass("NSScreen"), "mainScreen") orelse return 1.0;
    return send0(f64, screen, "backingScaleFactor");
}

pub export fn widget_cell_width() callconv(.c) f64 {
    var size: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
    if (std.posix.system.ioctl(std.posix.STDIN_FILENO, std.posix.T.IOCGWINSZ, &size) != 0 or size.col == 0) return 0;
    return @as(f64, @floatFromInt(size.xpixel)) / @as(f64, @floatFromInt(size.col));
}

pub export fn widget_cell_height() callconv(.c) f64 {
    var size: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
    if (std.posix.system.ioctl(std.posix.STDIN_FILENO, std.posix.T.IOCGWINSZ, &size) != 0 or size.row == 0) return 0;
    return @as(f64, @floatFromInt(size.ypixel)) / @as(f64, @floatFromInt(size.row));
}

pub export fn widget_monotonic_time() callconv(.c) f64 {
    var now: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.MONOTONIC, &now);
    return @as(f64, @floatFromInt(now.sec)) + @as(f64, @floatFromInt(now.nsec)) / 1e9;
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
    distance_sq: f64 = 0,
};

var snap_outline: Ref = null;
var snap_outline_rect = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } };
var snap_debug_panel: Ref = null;
var snap_debug_text: Ref = null;
var snap_outline_was_visible = false;
var snap_candidate_count: usize = 0;
var snap_last_distance_sq: f64 = 0;
var snap_last_visual: Point = .{ .x = 0, .y = 0 };
var snap_last_margin: Point = .{ .x = 0, .y = 0 };
var snap_debug_mode_mix: f64 = 0;
var snap_debug_card_width: f64 = 164;
var snap_debug_card_height: f64 = 164;
var snap_debug_dragging = false;

const KittyWindowInfo = struct { number: i64 = 0, layer: i64 = 0, frame: Rect = rect(0, 0, 0, 0) };

fn kittyPlayerWindowInfo() KittyWindowInfo {
    const list = CGWindowListCopyWindowInfo(1, 0) orelse return .{};
    defer CFRelease(list);
    const count = CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = CFArrayGetValueAtIndex(list, index);
        if (!stringEquals(CFDictionaryGetValue(info, macos.kCGWindowName), "spotify-player")) continue;
        const value = CFDictionaryGetValue(info, macos.kCGWindowNumber) orelse continue;
        var number: i64 = 0;
        if (!CFNumberGetValue(value, 4, @ptrCast(&number))) continue;
        var layer: i64 = 0;
        if (CFDictionaryGetValue(info, macos.kCGWindowLayer)) |layer_value| _ = CFNumberGetValue(layer_value, 4, @ptrCast(&layer));
        var frame: Rect = rect(0, 0, 0, 0);
        if (CFDictionaryGetValue(info, macos.kCGWindowBounds)) |bounds| _ = CGRectMakeWithDictionaryRepresentation(bounds, &frame);
        return .{ .number = number, .layer = layer, .frame = frame };
    }
    return .{};
}

fn setLabelText(label: Ref, value: []const u8) void {
    const ns_value = string(value);
    defer CFRelease(ns_value);
    send1(void, label, "setStringValue:", Ref, ns_value);
}

fn updateSnapDebug() void {
    // Drag and snap refreshes must never reopen a disabled inspector.
    if (!@import("../state.zig").setting_debug) {
        if (snap_debug_panel) |panel| send1(void, panel, "orderOut:", Ref, null);
        return;
    }
    if (snap_debug_panel == null) {
        const panel_cls = objc_getClass("NSPanel");
        const panel = send4(Ref, send0(Ref, panel_cls, "alloc"), "initWithContentRect:styleMask:backing:defer:", Rect, rect(24, 80, 440, 198), usize, 0, usize, 2, bool, false);
        if (panel == null) return;
        snap_debug_panel = panel;
        send1(void, panel, "setTitle:", Ref, string("Wallify Snap Debug"));
        send1(void, panel, "setLevel:", isize, 101);
        // NSPanel normally hides whenever its app deactivates. Kitty changes
        // activation while a panel moves, so make this an actual persistent
        // inspector rather than a transient utility panel.
        send1(void, panel, "setHidesOnDeactivate:", bool, false);
        send1(void, panel, "setReleasedWhenClosed:", bool, false);
        send1(void, panel, "setCollectionBehavior:", usize, 1 | 16 | 256);
        send1(void, panel, "setOpaque:", bool, false);
        send1(void, panel, "setBackgroundColor:", Ref, send0(Ref, objc_getClass("NSColor"), "clearColor"));
        send1(void, panel, "setIgnoresMouseEvents:", bool, true);
        const view = send0(Ref, panel, "contentView");
        send1(void, view, "setWantsLayer:", bool, true);
        const layer = send0(Ref, view, "layer");
        send1(void, layer, "setCornerRadius:", f64, 12);
        send1(void, layer, "setMasksToBounds:", bool, true);
        send1(void, layer, "setBackgroundColor:", Ref, send0(Ref, send2(Ref, objc_getClass("NSColor"), "colorWithWhite:alpha:", f64, 0.08, f64, 0.94), "CGColor"));
        send1(void, layer, "setBorderWidth:", f64, 1);
        send1(void, layer, "setBorderColor:", Ref, send0(Ref, send0(Ref, objc_getClass("NSColor"), "whiteColor"), "CGColor"));
        const label = send0(Ref, send0(Ref, objc_getClass("NSTextField"), "alloc"), "init");
        snap_debug_text = label;
        send1(void, label, "setFrame:", Rect, rect(14, 12, 412, 174));
        send1(void, label, "setEditable:", bool, false);
        send1(void, label, "setSelectable:", bool, false);
        send1(void, label, "setBezeled:", bool, false);
        send1(void, label, "setDrawsBackground:", bool, false);
        send1(void, label, "setTextColor:", Ref, send0(Ref, objc_getClass("NSColor"), "whiteColor"));
        send1(void, label, "setFont:", Ref, send2(Ref, objc_getClass("NSFont"), "monospacedSystemFontOfSize:weight:", f64, 12, f64, 0));
        send1(void, view, "addSubview:", Ref, label);
    }
    var message: [512]u8 = undefined;
    const actual = if (snap_outline) |panel| send0(Rect, panel, "frame") else rect(0, 0, 0, 0);
    const kitty = kittyPlayerWindowInfo();
    const screen = send0(Ref, objc_getClass("NSScreen"), "mainScreen");
    const screen_frame = if (screen) |value| send0(Rect, value, "frame") else rect(0, 0, 0, 0);
    const outline_level = if (snap_outline) |value| send0(isize, value, "level") else 0;
    const outline_number = if (snap_outline) |value| send0(isize, value, "windowNumber") else 0;
    const text = std.fmt.bufPrint(&message, "WALLIFY SNAP DEBUG  •  one process\nDrag={s}  mode mix={d:.2}  card={d:.0}×{d:.0}\nPreview ≤180  commit ≤150  candidates={d}  distance²={d:.0}\nMargins: x={d:.0} y={d:.0}  visual: x={d:.0} y={d:.0}\nTarget CG:  x={d:.0} y={d:.0}  {d:.0}×{d:.0}\nOutline: x={d:.0} y={d:.0}  {d:.0}×{d:.0} visible={s}\nOutline #{d} level={d}  screen={d:.0}×{d:.0}\nKitty CG #{d} layer={d}: x={d:.0} y={d:.0}  {d:.0}×{d:.0}", .{ if (snap_debug_dragging) "yes" else "no", snap_debug_mode_mix, snap_debug_card_width, snap_debug_card_height, snap_candidate_count, snap_last_distance_sq, snap_last_margin.x, snap_last_margin.y, snap_last_visual.x, snap_last_visual.y, snap_outline_rect.origin.x, snap_outline_rect.origin.y, snap_outline_rect.size.width, snap_outline_rect.size.height, actual.origin.x, actual.origin.y, actual.size.width, actual.size.height, if (snap_outline != null and send0(bool, snap_outline, "isVisible")) "yes" else "no", outline_number, outline_level, screen_frame.size.width, screen_frame.size.height, kitty.number, kitty.layer, kitty.frame.origin.x, kitty.frame.origin.y, kitty.frame.size.width, kitty.frame.size.height }) catch return;
    setLabelText(snap_debug_text, text);
    if (!send0(bool, snap_debug_panel, "isVisible")) {
        send1(void, snap_debug_panel, "setAlphaValue:", f64, 0);
        send0(void, snap_debug_panel, "orderFrontRegardless");
        send1(void, send0(Ref, snap_debug_panel, "animator"), "setAlphaValue:", f64, 1);
    } else send0(void, snap_debug_panel, "orderFrontRegardless");
}

fn updateSnapOutline(_: Ref) callconv(.c) void {
    const screen = send0(Ref, objc_getClass("NSScreen"), "mainScreen") orelse return;
    const screen_frame = send0(Rect, screen, "frame");
    // The native widget target preview sits just outside the destination's
    // rim. Keep its logical target exact, then expand only its visual shell.
    // The guide remains visible outside the card even when it is underneath
    // the moving player near the final drop location.
    const inset: f64 = 7;
    const preview_rect = rect(
        snap_outline_rect.origin.x - inset,
        snap_outline_rect.origin.y - inset,
        snap_outline_rect.size.width + inset * 2,
        snap_outline_rect.size.height + inset * 2,
    );
    // CGWindowList uses a top-left origin; AppKit windows use bottom-left.
    const frame = Rect{ .origin = .{
        .x = preview_rect.origin.x,
        .y = screen_frame.size.height - preview_rect.origin.y - preview_rect.size.height,
    }, .size = preview_rect.size };
    if (snap_outline == null) {
        const panel_cls = objc_getClass("NSPanel");
        const panel = send4(Ref, send0(Ref, panel_cls, "alloc"), "initWithContentRect:styleMask:backing:defer:", Rect, frame, usize, 0, usize, 2, bool, false);
        if (panel == null) return;
        snap_outline = panel;
        send1(void, panel, "setOpaque:", bool, false);
        // Native widget previews are a transparent guide, not a filled tile.
        send1(void, panel, "setBackgroundColor:", Ref, send0(Ref, objc_getClass("NSColor"), "clearColor"));
        send1(void, panel, "setAlphaValue:", f64, 1);
        send1(void, panel, "setIgnoresMouseEvents:", bool, true);
        send1(void, panel, "setHasShadow:", bool, false);
        send1(void, panel, "setHidesOnDeactivate:", bool, false);
        send1(void, panel, "setReleasedWhenClosed:", bool, false);
        // A level strictly below Kitty's panel ensures the guide stays underneath
        // the card even across separate process hierarchies.
        send1(void, panel, "setLevel:", isize, -2);
        // Keep the preview with the desktop across spaces and above the
        // wallpaper, without making it interactive or becoming a second app.
        send1(void, panel, "setCollectionBehavior:", usize, 1 | 16 | 256);
        // Do not depend on NSPanel's lazily-created default content view.
        // A dedicated layer-backed NSView is what AppKit reliably composites
        // for the persistent debug inspector as well.
        const view = send1(Ref, send0(Ref, objc_getClass("NSView"), "alloc"), "initWithFrame:", Rect, rect(0, 0, frame.size.width, frame.size.height));
        send1(void, panel, "setContentView:", Ref, view);
        send1(void, view, "setWantsLayer:", bool, true);
        const layer = send0(Ref, view, "layer");
        send1(void, layer, "setMasksToBounds:", bool, true);
        // Card rim is 26pt; the 5pt outer preview shell follows it at 31pt.
        send1(void, layer, "setCornerRadius:", f64, 31);
        send1(void, layer, "setBorderWidth:", f64, 3);
        const rim = send1(Ref, send0(Ref, objc_getClass("NSColor"), "systemGrayColor"), "colorWithAlphaComponent:", f64, 0.78);
        send1(void, layer, "setBorderColor:", Ref, send0(Ref, rim, "CGColor"));
        send1(void, layer, "setBackgroundColor:", Ref, send0(Ref, send0(Ref, objc_getClass("NSColor"), "clearColor"), "CGColor"));
    }
    send2(void, snap_outline, "setFrame:display:", Rect, frame, bool, true);
    const kitty_info = kittyPlayerWindowInfo();
    const target_level: isize = if (kitty_info.number > 0) @as(isize, @intCast(kitty_info.layer)) - 1 else -2;
    send1(void, snap_outline, "setLevel:", isize, target_level);
    send0(void, snap_outline, "orderFrontRegardless");
    if (!snap_outline_was_visible) {
        send1(void, snap_outline, "setAlphaValue:", f64, 0);
        send1(void, send0(Ref, snap_outline, "animator"), "setAlphaValue:", f64, 1);
        snap_outline_was_visible = true;
    }
    const content = send0(Ref, snap_outline, "contentView");
    send1(void, content, "setFrame:", Rect, rect(0, 0, frame.size.width, frame.size.height));
    updateSnapDebug();
}

fn hideSnapOutline(_: Ref) callconv(.c) void {
    if (snap_outline) |panel| send1(void, panel, "orderOut:", Ref, null);
    snap_outline_was_visible = false;
}

pub export fn widget_debug_window_show() callconv(.c) void {
    // Startup already runs on AppKit's main thread. Creating this synchronously
    // avoids waiting for the first mouse event to drain the main dispatch queue.
    updateSnapDebug();
}

pub export fn widget_debug_window_hide() callconv(.c) void {
    dispatch_async_f(dispatch_get_main_queue(), null, struct {
        fn hide(_: Ref) callconv(.c) void {
            if (snap_debug_panel) |panel| send1(void, panel, "orderOut:", Ref, null);
        }
    }.hide);
}

pub export fn widget_show_snap_outline(x: f64, y: f64, width: f64, height: f64) callconv(.c) void {
    snap_outline_rect = rect(x, y, width, height);
    dispatch_async_f(dispatch_get_main_queue(), null, updateSnapOutline);
}

pub export fn widget_set_snap_debug(mode_mix: f64, card_width: f64, card_height: f64, dragging: bool) callconv(.c) void {
    snap_debug_mode_mix = mode_mix;
    snap_debug_card_width = card_width;
    snap_debug_card_height = card_height;
    snap_debug_dragging = dragging;
    // The inspector must refresh even when the pointer is outside the preview
    // radius, otherwise expanded-mode diagnostics look stale.
    dispatch_async_f(dispatch_get_main_queue(), null, struct {
        fn refresh(_: Ref) callconv(.c) void {
            updateSnapDebug();
        }
    }.refresh);
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
        const bounds_dict = CFDictionaryGetValue(info, macos.kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        if (stringEquals(CFDictionaryGetValue(info, macos.kCGWindowName), "spotify-player")) {
            cached_offset_x = bounds.origin.x - @as(f64, @floatFromInt(margin_left));
            cached_offset_y = bounds.origin.y - @as(f64, @floatFromInt(margin_top));
            has_cached_offsets = true;
            return;
        }
        const owner = CFDictionaryGetValue(info, macos.kCGWindowOwnerName);
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
        const bounds_dict = CFDictionaryGetValue(info, macos.kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        const owner = CFDictionaryGetValue(info, macos.kCGWindowOwnerName);
        if (!stringEquals(owner, "Notification Center")) continue;
        if (bounds.size.width < 80 or bounds.size.height < 80 or bounds.size.width > 1400 or bounds.size.height > 800) continue;
        if (candidate_count < candidates.len) {
            candidates[candidate_count] = bounds;
            candidate_count += 1;
        }
    }

    const offset_x = if (has_cached_offsets) cached_offset_x else 0;
    const offset_y = if (has_cached_offsets) cached_offset_y else 0;
    const visual_x = offset_x + @as(f64, @floatFromInt(margin_left)) + visual_left;
    const visual_y = offset_y + @as(f64, @floatFromInt(margin_top)) + visual_top;
    snap_candidate_count = candidate_count;
    snap_last_margin = .{ .x = @floatFromInt(margin_left), .y = @floatFromInt(margin_top) };
    snap_last_visual = .{ .x = visual_x, .y = visual_y };

    const result = calculatePanelSnap(candidates[0..candidate_count], visual_x, visual_y, visual_width, visual_height, offset_x, offset_y, visual_left, visual_top);
    snap_last_distance_sq = result.distance_sq;
    return result;
}

pub fn calculatePanelSnap(
    candidates: []const Rect,
    visual_x: f64,
    visual_y: f64,
    visual_width: f64,
    visual_height: f64,
    offset_x: f64,
    offset_y: f64,
    visual_left: f64,
    visual_top: f64,
) PanelSnap {
    const grid_pitch: f64 = 180.0;
    // Align the rendered card rim, which sits a few points inside Kitty's
    // surface, rather than the surface's raw CGWindow bounds.
    const visible_rim_x: f64 = 8.0;
    const visible_rim_y: f64 = 8.0;
    // Capture begins while the player is still visibly approaching a widget;
    // on a large desktop, the former one-slot radius was too small to ever
    // expose a preview before mouse-up.
    const threshold_sq: f64 = 1100.0 * 1100.0;
    var best_dist = threshold_sq;
    var result = PanelSnap{};
    // Compact occupies one grid column. Expanded occupies three tiles, and
    // each of those columns is a valid alignment edge for a nearby widget.
    const player_columns: i32 = @max(1, @as(i32, @intFromFloat(@round((visual_width + 16.0) / grid_pitch))));

    for (candidates) |neighbor| {
        var col: i32 = 0;
        const columns: i32 = @max(1, @as(i32, @intFromFloat(@round(neighbor.size.width / grid_pitch))));
        while (col < columns) : (col += 1) {
            const cell_x = neighbor.origin.x + @as(f64, @floatFromInt(col)) * grid_pitch;
            var player_col: i32 = 0;
            while (player_col < player_columns) : (player_col += 1) {
                const aligned_left = cell_x - @as(f64, @floatFromInt(player_col)) * grid_pitch + visible_rim_x;
                const targets = [_]Point{
                    .{ .x = aligned_left, .y = neighbor.origin.y - visual_height - visible_rim_y },
                    .{ .x = aligned_left, .y = neighbor.origin.y + neighbor.size.height + visible_rim_y },
                };
                for (targets) |target| {
                    const dx = target.x - visual_x;
                    const dy = target.y - visual_y;
                    const dist_sq = dx * dx + dy * dy;
                    if (dist_sq < best_dist) {
                        best_dist = dist_sq;
                        result = .{
                            .found = true,
                            .margin_left = @as(i32, @intFromFloat(@round(target.x - offset_x - visual_left))),
                            .margin_top = @as(i32, @intFromFloat(@round(target.y - offset_y - visual_top))),
                            .outline_x = target.x,
                            .outline_y = target.y,
                            .outline_width = visual_width,
                            .outline_height = visual_height,
                            .distance_sq = dist_sq,
                        };
                    }
                }
            }
        }
        const side_targets = [_]Point{
            .{ .x = neighbor.origin.x - visual_width - visible_rim_x, .y = neighbor.origin.y + visible_rim_y },
            .{ .x = neighbor.origin.x + neighbor.size.width + visible_rim_x, .y = neighbor.origin.y + visible_rim_y },
        };
        for (side_targets) |target| {
            const dx = target.x - visual_x;
            const dy = target.y - visual_y;
            const distance = dx * dx + dy * dy;
            if (distance < best_dist) {
                best_dist = distance;
                result = .{
                    .found = true,
                    .margin_left = @as(i32, @intFromFloat(@round(target.x - offset_x - visual_left))),
                    .margin_top = @as(i32, @intFromFloat(@round(target.y - offset_y - visual_top))),
                    .outline_x = target.x,
                    .outline_y = target.y,
                    .outline_width = visual_width,
                    .outline_height = visual_height,
                    .distance_sq = distance,
                };
            }
        }
    }
    return result;
}

test "panel snap returns not found when candidates list is empty" {
    const snap = calculatePanelSnap(&.{}, 100, 100, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(!snap.found);
    try std.testing.expectEqual(@as(f64, 0), snap.distance_sq);
}

test "panel snap vertically aligns above/below neighboring widget" {
    // Neighbor at x=200, y=300, size 180x180
    const neighbor = rect(200, 300, 180, 180);
    const candidates = [_]Rect{neighbor};

    // Approach from below the neighbor: visual_y=500
    const snap_below = calculatePanelSnap(&candidates, 208, 495, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_below.found);
    // Expected y target: neighbor.y + neighbor.h + visible_rim_y = 300 + 180 + 8 = 488
    try std.testing.expectEqual(@as(f64, 488), snap_below.outline_y);
    try std.testing.expectEqual(@as(f64, 208), snap_below.outline_x);

    // Approach from above the neighbor: visual_y=120
    const snap_above = calculatePanelSnap(&candidates, 208, 125, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_above.found);
    // Expected y target: neighbor.y - visual_h - visible_rim_y = 300 - 164 - 8 = 128
    try std.testing.expectEqual(@as(f64, 128), snap_above.outline_y);
}

test "panel snap horizontally aligns to neighboring widget sides" {
    // Neighbor at x=400, y=200, size 180x180
    const neighbor = rect(400, 200, 180, 180);
    const candidates = [_]Rect{neighbor};

    // Approach from the right: visual_x=590, visual_y=208
    const snap_right = calculatePanelSnap(&candidates, 590, 208, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_right.found);
    // Expected target x: neighbor.x + neighbor.w + visible_rim_x = 400 + 180 + 8 = 588
    try std.testing.expectEqual(@as(f64, 588), snap_right.outline_x);
    try std.testing.expectEqual(@as(f64, 208), snap_right.outline_y);

    // Approach from the left: visual_x=225, visual_y=208
    const snap_left = calculatePanelSnap(&candidates, 225, 208, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_left.found);
    // Expected target x: neighbor.x - visual_w - visible_rim_x = 400 - 164 - 8 = 228
    try std.testing.expectEqual(@as(f64, 228), snap_left.outline_x);
}

test "panel snap rejects candidates beyond distance threshold" {
    const neighbor = rect(2000, 2000, 180, 180);
    const candidates = [_]Rect{neighbor};
    const snap = calculatePanelSnap(&candidates, 100, 100, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(!snap.found);
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
