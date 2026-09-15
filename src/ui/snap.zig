const std = @import("std");
const macos = @import("../platform/macos.zig");
const state = @import("../state.zig");

const Ref = macos.Ref;
const Point = macos.Point;
const Rect = macos.Rect;
const rect = macos.rect;

// Grid metrics & snap tuning
const GRID_PITCH: f64 = state.Layout.grid_pitch;
const VISIBLE_RIM: f64 = 8.0;
const SNAP_PREVIEW_INSET: f64 = 7.0;
const SNAP_THRESHOLD: f64 = 1100.0 * 1100.0;
const MAX_CANDIDATE_WIDTH: f64 = 1400.0;
const MAX_CANDIDATE_HEIGHT: f64 = 800.0;
const MIN_CANDIDATE_SIZE: f64 = 80.0;
const OUTLINE_RADIUS: f64 = 31.0;
const DEBUG_PANEL_LEVEL: isize = 101;
const OUTLINE_LEVEL_FALLBACK: isize = -2;

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

const PanelWindowInfo = struct {
    number: i64 = 0,
    layer: i64 = 0,
    frame: Rect = rect(0, 0, 0, 0),
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
var snap_debug_card_width: f64 = state.Layout.compact_content_width;
var snap_debug_card_height: f64 = state.Layout.compact_content_height;
var snap_debug_dragging = false;

var cached_offset_x: f64 = 0;
var cached_offset_y: f64 = 36;
var has_cached_offsets: bool = false;

fn stringEquals(value: Ref, expected: []const u8) bool {
    if (value == null) return false;
    var buffer: [128]u8 = undefined;
    if (macos.CFStringGetCString(value, &buffer, buffer.len, 0x08000100) == 0) return false;
    return std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), expected);
}

fn isPlayerWindow(info: Ref) bool {
    const owner = macos.CFDictionaryGetValue(info, macos.kCGWindowOwnerName);
    const name = macos.CFDictionaryGetValue(info, macos.kCGWindowName);
    const matches = stringEquals(name, "Wallify") or stringEquals(owner, "Wallify");
    if (!matches) return false;
    if (name) |n| {
        if (stringEquals(n, "Wallify Snap Debug")) return false;
    }
    return true;
}

fn playerWindowInfo() PanelWindowInfo {
    const list = macos.CGWindowListCopyWindowInfo(1, 0) orelse return .{};
    defer macos.CFRelease(list);
    const count = macos.CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = macos.CFArrayGetValueAtIndex(list, index);
        if (!isPlayerWindow(info)) continue;
        const value = macos.CFDictionaryGetValue(info, macos.kCGWindowNumber) orelse continue;
        var number: i64 = 0;
        if (!macos.CFNumberGetValue(value, 4, @ptrCast(&number))) continue;
        var layer: i64 = 0;
        if (macos.CFDictionaryGetValue(info, macos.kCGWindowLayer)) |layer_value| _ = macos.CFNumberGetValue(layer_value, 4, @ptrCast(&layer));
        var frame: Rect = rect(0, 0, 0, 0);
        if (macos.CFDictionaryGetValue(info, macos.kCGWindowBounds)) |bounds| _ = macos.CGRectMakeWithDictionaryRepresentation(bounds, &frame);
        return .{ .number = number, .layer = layer, .frame = frame };
    }
    return .{};
}

fn setLabelText(label: Ref, value: []const u8) void {
    const ns_value = macos.string(value);
    defer macos.CFRelease(ns_value);
    macos.send(void, label, "setStringValue:", .{ns_value});
}

fn updateSnapDebug() void {
    if (!state.setting_debug) {
        if (snap_debug_panel) |panel| macos.send(void, panel, "orderOut:", .{@as(Ref, null)});
        return;
    }
    if (snap_debug_panel == null) {
        const panel_cls = macos.objc_getClass("NSPanel");
        const panel = macos.send(Ref, macos.send(Ref, panel_cls, "alloc", .{}), "initWithContentRect:styleMask:backing:defer:", .{ rect(24, 60, 340, 240), @as(usize, 1 | 2), @as(usize, 2), false });
        if (panel == null) return;
        snap_debug_panel = panel;
        macos.send(void, panel, "setTitle:", .{macos.string("Wallify Snap Debug")});
        macos.send(void, panel, "setFloatingPanel:", .{true});
        macos.send(void, panel, "setLevel:", .{@as(isize, DEBUG_PANEL_LEVEL)});
        macos.send(void, panel, "setHidesOnDeactivate:", .{false});
        macos.send(void, panel, "setReleasedWhenClosed:", .{false});

        const label_cls = macos.objc_getClass("NSTextField");
        const label = macos.send(Ref, macos.send(Ref, label_cls, "alloc", .{}), "initWithFrame:", .{rect(12, 12, 316, 216)});
        if (label == null) return;
        snap_debug_text = label;
        macos.send(void, label, "setEditable:", .{false});
        macos.send(void, label, "setSelectable:", .{true});
        macos.send(void, label, "setBezeled:", .{false});
        macos.send(void, label, "setDrawsBackground:", .{false});
        const font = macos.send(Ref, macos.objc_getClass("NSFont"), "monospacedSystemFontOfSize:weight:", .{ @as(f64, 11.0), @as(f64, 0.0) });
        if (font != null) macos.send(void, label, "setFont:", .{font});

        const content = macos.send(Ref, panel, "contentView", .{});
        macos.send(void, content, "addSubview:", .{label});
    }

    const actual = if (snap_outline) |panel| macos.send(Rect, panel, "frame", .{}) else rect(0, 0, 0, 0);
    const outline_number = if (snap_outline) |value| macos.send(isize, value, "windowNumber", .{}) else 0;
    const outline_level = if (snap_outline) |value| macos.send(isize, value, "level", .{}) else 0;
    const player = playerWindowInfo();
    const screen = macos.send(Ref, macos.objc_getClass("NSScreen"), "mainScreen", .{}) orelse return;
    const screen_frame = macos.send(Rect, screen, "frame", .{});
    var message: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&message, "WALLIFY SNAP DEBUG  •  one process\nDrag={s}  mode mix={d:.2}  card={d:.0}×{d:.0}\nPreview ≤180  commit ≤150  candidates={d}  distance²={d:.0}\nMargins: x={d:.0} y={d:.0}  visual: x={d:.0} y={d:.0}\nTarget CG:  x={d:.0} y={d:.0}  {d:.0}×{d:.0}\nOutline: x={d:.0} y={d:.0}  {d:.0}×{d:.0} visible={s}\nOutline #{d} level={d}  screen={d:.0}×{d:.0}\nWallify CG #{d} layer={d}: x={d:.0} y={d:.0}  {d:.0}×{d:.0}", .{ if (snap_debug_dragging) "yes" else "no", snap_debug_mode_mix, snap_debug_card_width, snap_debug_card_height, snap_candidate_count, snap_last_distance_sq, snap_last_margin.x, snap_last_margin.y, snap_last_visual.x, snap_last_visual.y, snap_outline_rect.origin.x, snap_outline_rect.origin.y, snap_outline_rect.size.width, snap_outline_rect.size.height, actual.origin.x, actual.origin.y, actual.size.width, actual.size.height, if (snap_outline != null and macos.send(bool, snap_outline, "isVisible", .{})) "yes" else "no", outline_number, outline_level, screen_frame.size.width, screen_frame.size.height, player.number, player.layer, player.frame.origin.x, player.frame.origin.y, player.frame.size.width, player.frame.size.height }) catch return;
    setLabelText(snap_debug_text, text);
    if (!macos.send(bool, snap_debug_panel, "isVisible", .{})) {
        macos.send(void, snap_debug_panel, "setAlphaValue:", .{@as(f64, 0)});
        macos.send(void, snap_debug_panel, "orderFrontRegardless", .{});
        macos.send(void, macos.send(Ref, snap_debug_panel, "animator", .{}), "setAlphaValue:", .{@as(f64, 1)});
    } else macos.send(void, snap_debug_panel, "orderFrontRegardless", .{});
}

fn updateSnapOutline(_: Ref) callconv(.c) void {
    const screen = macos.send(Ref, macos.objc_getClass("NSScreen"), "mainScreen", .{}) orelse return;
    const screen_frame = macos.send(Rect, screen, "frame", .{});
    // The native widget target preview sits just outside the destination's
    // rim. Keep its logical target exact, then expand only its visual shell.
    // The guide remains visible outside the card even when it is underneath
    // the moving player near the final drop location.
    const inset: f64 = SNAP_PREVIEW_INSET;
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
        const panel_cls = macos.objc_getClass("NSPanel");
        const panel = macos.send(Ref, macos.send(Ref, panel_cls, "alloc", .{}), "initWithContentRect:styleMask:backing:defer:", .{ frame, @as(usize, 0), @as(usize, 2), false });
        if (panel == null) return;
        snap_outline = panel;
        macos.send(void, panel, "setOpaque:", .{false});
        macos.send(void, panel, "setBackgroundColor:", .{macos.send(Ref, macos.objc_getClass("NSColor"), "clearColor", .{})});
        macos.send(void, panel, "setAlphaValue:", .{@as(f64, 1)});
        macos.send(void, panel, "setIgnoresMouseEvents:", .{true});
        macos.send(void, panel, "setHasShadow:", .{false});
        macos.send(void, panel, "setHidesOnDeactivate:", .{false});
        macos.send(void, panel, "setReleasedWhenClosed:", .{false});
        macos.send(void, panel, "setLevel:", .{@as(isize, -2)});
        macos.send(void, panel, "setCollectionBehavior:", .{@as(usize, 1 | 16 | 256)});

        const view = macos.send(Ref, macos.send(Ref, macos.objc_getClass("NSView"), "alloc", .{}), "initWithFrame:", .{rect(0, 0, frame.size.width, frame.size.height)});
        macos.send(void, panel, "setContentView:", .{view});
        macos.send(void, view, "setWantsLayer:", .{true});
        const layer = macos.send(Ref, view, "layer", .{});
        macos.send(void, layer, "setMasksToBounds:", .{true});
        macos.send(void, layer, "setCornerRadius:", .{@as(f64, OUTLINE_RADIUS)});
        macos.send(void, layer, "setBorderWidth:", .{@as(f64, 3)});
        const rim = macos.send(Ref, macos.send(Ref, macos.objc_getClass("NSColor"), "systemGrayColor", .{}), "colorWithAlphaComponent:", .{@as(f64, 0.78)});
        macos.send(void, layer, "setBorderColor:", .{macos.send(Ref, rim, "CGColor", .{})});
        macos.send(void, layer, "setBackgroundColor:", .{macos.send(Ref, macos.send(Ref, macos.objc_getClass("NSColor"), "clearColor", .{}), "CGColor", .{})});
    }
    macos.send(void, snap_outline, "setFrame:display:", .{ frame, true });
    const panel_info = playerWindowInfo();
    const target_level: isize = if (panel_info.number > 0) @as(isize, @intCast(panel_info.layer)) - 1 else OUTLINE_LEVEL_FALLBACK;
    macos.send(void, snap_outline, "setLevel:", .{target_level});
    macos.send(void, snap_outline, "orderFrontRegardless", .{});
    if (!snap_outline_was_visible) {
        macos.send(void, snap_outline, "setAlphaValue:", .{@as(f64, 0)});
        macos.send(void, macos.send(Ref, snap_outline, "animator", .{}), "setAlphaValue:", .{@as(f64, 1)});
        snap_outline_was_visible = true;
    }
    const content = macos.send(Ref, snap_outline, "contentView", .{});
    macos.send(void, content, "setFrame:", .{rect(0, 0, frame.size.width, frame.size.height)});
    updateSnapDebug();
}

fn hideSnapOutline(_: Ref) callconv(.c) void {
    if (snap_outline) |panel| macos.send(void, panel, "orderOut:", .{@as(Ref, null)});
    snap_outline_was_visible = false;
}

pub export fn widget_debug_window_show() callconv(.c) void {
    updateSnapDebug();
}

pub export fn widget_debug_window_hide() callconv(.c) void {
    macos.dispatch_async_f(macos.dispatch_get_main_queue(), null, struct {
        fn hide(_: Ref) callconv(.c) void {
            if (snap_debug_panel) |panel| macos.send(void, panel, "orderOut:", .{@as(Ref, null)});
        }
    }.hide);
}

pub export fn widget_show_snap_outline(x: f64, y: f64, width: f64, height: f64) callconv(.c) void {
    snap_outline_rect = rect(x, y, width, height);
    macos.dispatch_async_f(macos.dispatch_get_main_queue(), null, updateSnapOutline);
}

pub export fn widget_set_snap_debug(mode_mix: f64, card_width: f64, card_height: f64, dragging: bool) callconv(.c) void {
    snap_debug_mode_mix = mode_mix;
    snap_debug_card_width = card_width;
    snap_debug_card_height = card_height;
    snap_debug_dragging = dragging;
    macos.dispatch_async_f(macos.dispatch_get_main_queue(), null, struct {
        fn refresh(_: Ref) callconv(.c) void {
            updateSnapDebug();
        }
    }.refresh);
}

pub export fn widget_hide_snap_outline() callconv(.c) void {
    macos.dispatch_async_f(macos.dispatch_get_main_queue(), null, hideSnapOutline);
}

pub export fn widget_start_drag(margin_left: i32, margin_top: i32, visual_width: f64) callconv(.c) void {
    _ = visual_width;
    const list = macos.CGWindowListCopyWindowInfo(1, 0) orelse return;
    defer macos.CFRelease(list);
    const count = macos.CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = macos.CFArrayGetValueAtIndex(list, index);
        const bounds_dict = macos.CFDictionaryGetValue(info, macos.kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!macos.CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        if (isPlayerWindow(info)) {
            cached_offset_x = bounds.origin.x - @as(f64, @floatFromInt(margin_left));
            cached_offset_y = bounds.origin.y - @as(f64, @floatFromInt(margin_top));
            has_cached_offsets = true;
            return;
        }
    }
}

pub export fn widget_nearby_panel_snap(margin_left: i32, margin_top: i32, visual_left: f64, visual_top: f64, visual_width: f64, visual_height: f64) callconv(.c) PanelSnap {
    const list = macos.CGWindowListCopyWindowInfo(1, 0) orelse return .{};
    defer macos.CFRelease(list);

    var candidates: [64]Rect = undefined;
    var candidate_count: usize = 0;
    const count = macos.CFArrayGetCount(list);
    var index: isize = 0;
    while (index < count) : (index += 1) {
        const info = macos.CFArrayGetValueAtIndex(list, index);
        const bounds_dict = macos.CFDictionaryGetValue(info, macos.kCGWindowBounds) orelse continue;
        var bounds: Rect = undefined;
        if (!macos.CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds)) continue;
        const owner = macos.CFDictionaryGetValue(info, macos.kCGWindowOwnerName);
        if (!stringEquals(owner, "Notification Center") and !stringEquals(owner, "NotificationCenter")) continue;

        // Notification Center hosts both interactive desktop widgets and an assortment
        // of internal scratch surfaces (cached render targets, off-screen drawers, and
        // slide-out sidebars). Because macOS TCC redacts `kCGWindowName` for foreign
        // processes without Screen Recording entitlement, we identify genuine desktop
        // tiles through physical WindowServer properties:
        //
        // 1. Transparency: Scratch buffers linger with alpha = 0.0, while visible
        //    tiles are fully composited.
        // 2. Layering: Desktop widgets live exclusively on the desktop icon plane
        //    (-2147483601). Notification alerts float high above (>= 0), while
        //    hidden background caches drop to -2147483602.
        // 3. Geometry: Discard staging rects that sit completely off-screen.
        if (macos.CFDictionaryGetValue(info, macos.kCGWindowAlpha)) |alpha_ref| {
            var alpha: f64 = 1.0;
            if (macos.CFNumberGetValue(alpha_ref, 13, @ptrCast(&alpha))) {
                if (alpha < 0.5) continue;
            }
        }

        var layer: i64 = 0;
        if (macos.CFDictionaryGetValue(info, macos.kCGWindowLayer)) |layer_ref| {
            _ = macos.CFNumberGetValue(layer_ref, 4, @ptrCast(&layer));
        }
        if (layer >= 0 or layer == -2147483602) continue;

        if (bounds.origin.x + bounds.size.width <= 0 or bounds.origin.y + bounds.size.height <= 0) continue;
        if (bounds.size.width < MIN_CANDIDATE_SIZE or bounds.size.height < MIN_CANDIDATE_SIZE or bounds.size.width > MAX_CANDIDATE_WIDTH or bounds.size.height > MAX_CANDIDATE_HEIGHT) continue;
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
    const grid_pitch: f64 = GRID_PITCH;
    const visible_rim_x: f64 = VISIBLE_RIM;
    const visible_rim_y: f64 = VISIBLE_RIM;
    const threshold_sq: f64 = SNAP_THRESHOLD;
    var best_dist = threshold_sq;
    var result = PanelSnap{};
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
    const neighbor = rect(200, 300, 180, 180);
    const candidates = [_]Rect{neighbor};

    const snap_below = calculatePanelSnap(&candidates, 208, 495, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_below.found);
    try std.testing.expectEqual(@as(f64, 488), snap_below.outline_y);
    try std.testing.expectEqual(@as(f64, 208), snap_below.outline_x);

    const snap_above = calculatePanelSnap(&candidates, 208, 125, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_above.found);
    try std.testing.expectEqual(@as(f64, 128), snap_above.outline_y);
}

test "panel snap horizontally aligns to neighboring widget sides" {
    const neighbor = rect(400, 200, 180, 180);
    const candidates = [_]Rect{neighbor};

    const snap_right = calculatePanelSnap(&candidates, 590, 208, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_right.found);
    try std.testing.expectEqual(@as(f64, 588), snap_right.outline_x);
    try std.testing.expectEqual(@as(f64, 208), snap_right.outline_y);

    const snap_left = calculatePanelSnap(&candidates, 225, 208, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(snap_left.found);
    try std.testing.expectEqual(@as(f64, 228), snap_left.outline_x);
}

test "panel snap rejects candidates beyond distance threshold" {
    const neighbor = rect(2000, 2000, 180, 180);
    const candidates = [_]Rect{neighbor};
    const snap = calculatePanelSnap(&candidates, 100, 100, 164, 164, 0, 0, 0, 0);
    try std.testing.expect(!snap.found);
}
