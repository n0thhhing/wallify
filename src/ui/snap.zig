const std = @import("std");
const macos = @import("../platform/macos.zig");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");
const build_options = @import("build_options");
const debug_imgui = if (build_options.debug_inspector) @import("debug_imgui.zig") else struct {
    pub fn show() void {}
    pub fn hide() void {}
};

const Ref = macos.Ref;
const Point = macos.Point;
const Rect = macos.Rect;
const rect = macos.rect;

// Grid metrics & snap tuning
// macOS Sequoia arranges small desktop widgets in 180×180pt tiles.
const OUTLINE_RADIUS: f64 = state.Layout.card_radius;

pub const PanelSnap = native.gpu.WallifyPanelSnap;
extern fn wallify_calculate_panel_snap(candidates: [*]const native.gpu.WallifyWindowRect, count: usize, visual_x: f64, visual_y: f64, width: f64, height: f64, offset_x: f64, offset_y: f64, inset_x: f64, inset_y: f64, output: *PanelSnap) callconv(.c) void;

const PanelWindowInfo = struct {
    number: i64 = 0,
    layer: i64 = 0,
    frame: Rect = rect(0, 0, 0, 0),
};

var snap_outline_rect = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 0, .height = 0 } };
var snap_candidate_count: usize = 0;
var snap_last_distance_sq: f64 = 0;
var snap_last_visual: Point = .{ .x = 0, .y = 0 };
var snap_last_margin: Point = .{ .x = 0, .y = 0 };
var snap_debug_mode_mix: f64 = 0;
var snap_debug_card_width: f64 = state.Layout.compact_content_width;
var snap_debug_card_height: f64 = state.Layout.compact_content_height;
var snap_debug_dragging = false;

// WindowServer (CGWindowList) coordinates start from top-left of the display.
// AppKit panel margins are positioned relative to the visible screen frame (below the 33pt menu bar).
// These offsets bridge the two coordinate frames during drags.
var cached_offset_x: f64 = 0;
var cached_offset_y: f64 = 33;
var has_cached_offsets: bool = false;

extern "c" fn wallify_query_player_window(out: *native.gpu.WallifyWindowInfo) void;
extern "c" fn wallify_desktop_candidates(out: [*]native.gpu.WallifyWindowRect, capacity: usize) usize;
extern "c" fn wallify_show_snap_preview(x: f64, y: f64, width: f64, height: f64, radius: f64) void;
extern "c" fn wallify_hide_snap_preview() void;

fn playerWindowInfo() PanelWindowInfo {
    var info: native.gpu.WallifyWindowInfo = undefined;
    wallify_query_player_window(&info);
    return .{ .number = info.number, .layer = info.layer, .frame = rect(info.frame.x, info.frame.y, info.frame.width, info.frame.height) };
}

// One C definition keeps the Zig writer and inspector reader ABI in sync.
pub const DebugSnapshot = native.gpu.WallifyDebugSnapshot;

fn debugApplyBool(key: isize, value: bool) void {
    switch (key) {
        0 => state.shared().setting_glow = value,
        1 => state.shared().setting_aurora = value,
        2 => state.shared().setting_animations = value,
        3 => state.shared().setting_dim = value,
        5 => state.shared().setting_native_glass = value,
        6 => state.shared().setting_hide_text = value,
        7 => state.shared().setting_hide_progress = value,
        8 => state.shared().setting_show_controls = value,
        9 => state.shared().setting_show_timestamps = value,
        19 => state.shared().setting_artwork_border = value,
        20 => state.shared().setting_compact_gradient = value,
        else => {},
    }
    state.saveWidgetSettings();
    state.requestFrame();
}

fn debugApplyInt(key: isize, value: isize) void {
    switch (key) {
        10 => state.shared().setting_frame = @enumFromInt(std.math.clamp(value, 0, 2)),
        11 => state.shared().setting_intensity = @enumFromInt(std.math.clamp(value, 0, 2)),
        12 => state.shared().setting_speed = @enumFromInt(std.math.clamp(value, 0, 2)),
        13 => state.shared().setting_source = @enumFromInt(std.math.clamp(value, 0, 3)),
        14 => {
            const mode: state.WidgetMode = @enumFromInt(std.math.clamp(value, 0, 4));
            const width: f64 = @floatFromInt(native.wallify_width());
            const height: f64 = @floatFromInt(native.wallify_height());
            state.beginModeTransition(mode, width, height, state.shared().setting_animations);
            if (!state.shared().mode_transition_active) native.resizeForMode(mode);
        },
        16 => state.shared().setting_transition = @enumFromInt(std.math.clamp(value, 0, 5)),
        17 => state.shared().setting_font_scale = @enumFromInt(std.math.clamp(value, 0, 2)),
        18 => {
            state.shared().setting_media_key_target = @enumFromInt(std.math.clamp(value, 0, 3));
            native.wallify_update_media_key_tap(@intCast(value));
        },
        21 => state.shared().setting_artwork_radius = @enumFromInt(std.math.clamp(value, 0, 2)),
        22 => state.shared().setting_progress_thickness = @enumFromInt(std.math.clamp(value, 0, 2)),
        1000 => snap_debug_mode_mix = std.math.clamp(@as(f64, @floatFromInt(value)) / 100.0, 0.0, 1.0),
        1001 => {
            snap_debug_card_width = @max(1.0, @as(f64, @floatFromInt(value)));
            native.resizeTo(snap_debug_card_width, @floatFromInt(native.wallify_height()));
        },
        1002 => {
            snap_debug_card_height = @max(1.0, @as(f64, @floatFromInt(value)));
            native.resizeTo(@floatFromInt(native.wallify_width()), snap_debug_card_height);
        },
        1003 => {
            state.shared().widget_margin_left = @intCast(value);
            state.shared().panel_position_dirty = true;
            native.wallify_move(state.shared().widget_margin_left, state.shared().widget_margin_top);
        },
        1004 => {
            state.shared().widget_margin_top = @intCast(value);
            state.shared().panel_position_dirty = true;
            native.wallify_move(state.shared().widget_margin_left, state.shared().widget_margin_top);
        },
        1005 => snap_outline_rect.origin.x = @floatFromInt(value),
        1006 => snap_outline_rect.origin.y = @floatFromInt(value),
        1007 => snap_outline_rect.size.width = @max(1.0, @as(f64, @floatFromInt(value))),
        1008 => snap_outline_rect.size.height = @max(1.0, @as(f64, @floatFromInt(value))),
        else => {},
    }
    state.saveWidgetSettings();
    state.requestFrame();
}

pub export fn wallify_debug_get_snapshot(out: *DebugSnapshot) callconv(.c) void {
    const player = playerWindowInfo();
    const actual = player.frame;
    // The scene renderer updates layout on its worker thread.
    const window = @import("window.zig");
    window.widget_render_lock();
    defer window.widget_render_unlock();
    const layout = state.layout;
    const card = layout.card(state.shared().mode_mix);
    const controls_visible: u32 = @intFromBool(layout.controlsVisible(state.shared().setting_show_controls) and !state.spotifyIdle());
    const progress_visible: u32 = @intFromBool(layout.progressVisible(state.shared().setting_hide_progress) and !state.spotifyIdle());
    out.* = .{
        .glow = @intFromBool(state.shared().setting_glow),
        .aurora = @intFromBool(state.shared().setting_aurora),
        .animations = @intFromBool(state.shared().setting_animations),
        .dim = @intFromBool(state.shared().setting_dim),
        .native_glass = @intFromBool(state.shared().setting_native_glass),
        .hide_text = @intFromBool(state.shared().setting_hide_text),
        .hide_progress = @intFromBool(state.shared().setting_hide_progress),
        .show_controls = @intFromBool(state.shared().setting_show_controls),
        .timestamps = @intFromBool(state.shared().setting_show_timestamps),
        .artwork_border = @intFromBool(state.shared().setting_artwork_border),
        .compact_gradient = @intFromBool(state.shared().setting_compact_gradient),
        .frame = @intFromEnum(state.shared().setting_frame),
        .intensity = @intFromEnum(state.shared().setting_intensity),
        .speed = @intFromEnum(state.shared().setting_speed),
        .source = @intFromEnum(state.shared().setting_source),
        .mode = @intFromEnum(state.shared().setting_mode),
        .transition = @intFromEnum(state.shared().setting_transition),
        .font_scale = @intFromEnum(state.shared().setting_font_scale),
        .media_key_target = @intFromEnum(state.shared().setting_media_key_target),
        .artwork_radius = @intFromEnum(state.shared().setting_artwork_radius),
        .progress_thickness = @intFromEnum(state.shared().setting_progress_thickness),
        .width = native.wallify_width(),
        .height = native.wallify_height(),
        .margin_left = state.shared().widget_margin_left,
        .margin_top = state.shared().widget_margin_top,
        .dragging = @intFromBool(snap_debug_dragging),
        .window_number = player.number,
        .window_layer = player.layer,
        .window_x = actual.origin.x,
        .window_y = actual.origin.y,
        .window_width = actual.size.width,
        .window_height = actual.size.height,
        .outline_x = snap_outline_rect.origin.x,
        .outline_y = snap_outline_rect.origin.y,
        .outline_width = snap_outline_rect.size.width,
        .outline_height = snap_outline_rect.size.height,
        .candidate_count = @intCast(snap_candidate_count),
        .snap_distance_sq = snap_last_distance_sq,
        .mode_mix = @floatCast(snap_debug_mode_mix),
        .title_len = @intCast(@min(state.shared().global_title_len, 255)),
        .artist_len = @intCast(@min(state.shared().global_artist_len, 255)),
        .title = [_]u8{0} ** 256,
        .artist = [_]u8{0} ** 256,
        .pointer_x = state.shared().pointer_x,
        .pointer_y = state.shared().pointer_y,
        .hover_target = @intFromEnum(state.shared().global_hover_target),
        .click_target = @intFromEnum(state.shared().global_click_target),
        .seeking = @intFromBool(state.shared().global_is_dragging),
        .panel_dragging = @intFromBool(state.shared().global_panel_dragging),
        .transition_active = @intFromBool(state.shared().mode_transition_active),
        .frame_requested = @intFromBool(state.frame_requested.load(.acquire)),
        .has_artwork = @intFromBool(state.shared().global_has_artwork),
        .snap_active = @intFromBool(state.shared().panel_snap_active),
        .layout_width = layout.width,
        .layout_height = layout.height,
        .compact_mix = layout.compact_mix,
        .transition_mix = state.shared().mode_mix,
        .idle_mix = state.shared().idle_mix,
        .aurora_mix = state.shared().aurora_mix,
        .artwork_mix = state.shared().global_art_crossfade_alpha,
        .play_pause_mix = state.shared().play_pause_mix,
        .position = state.shared().global_position,
        .duration = state.shared().global_duration,
        .rate = state.shared().global_rate,
        .geometry = .{
            .{ card.x, card.y, card.w, card.h, card.radius },
            .{ layout.art_x, layout.art_y, layout.art_size, layout.art_size, layout.art_radius },
            .{ layout.bar_x, layout.bar_y, layout.bar_w, layout.bar_h, 0 },
            .{ layout.bar_x, layout.bar_y - layout.bar_hit_pad_y, layout.bar_w, layout.bar_h + 2 * layout.bar_hit_pad_y, 3 },
            .{ 0, 0, 0, 0, 0 },
            .{ 0, 0, 0, 0, 0 },
            .{ 0, 0, 0, 0, 0 },
        },
        .geometry_visible = .{ 1, @intFromBool(!state.spotifyIdle()), progress_visible, progress_visible, controls_visible, controls_visible, controls_visible },
    };
    for (layout.buttons, 4..) |button, i| {
        const bounds = button.bounds();
        out.geometry[i] = .{ bounds.x, bounds.y, bounds.w, bounds.h, bounds.radius };
    }
    std.mem.copyForwards(u8, out.title[0..out.title_len], state.shared().global_title[0..out.title_len]);
    std.mem.copyForwards(u8, out.artist[0..out.artist_len], state.shared().global_artist[0..out.artist_len]);
}

pub export fn wallify_debug_set_bool(key: c_int, value: c_int) callconv(.c) void {
    debugApplyBool(@intCast(key), value != 0);
}

pub export fn wallify_debug_set_int(key: c_int, value: c_int) callconv(.c) void {
    debugApplyInt(@intCast(key), value);
    updateSnapDebug();
}

fn updateSnapDebug() void {
    if (!state.shared().setting_debug) {
        debug_imgui.hide();
        return;
    }
    debug_imgui.show();
}

pub export fn widget_debug_window_show() callconv(.c) void {
    updateSnapDebug();
}

pub export fn widget_debug_window_hide() callconv(.c) void {
    debug_imgui.hide();
}

pub export fn widget_show_snap_outline(x: f64, y: f64, width: f64, height: f64) callconv(.c) void {
    snap_outline_rect = rect(x, y, width, height);
    wallify_show_snap_preview(x, y, width, height, OUTLINE_RADIUS);
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
    wallify_hide_snap_preview();
}

pub export fn widget_start_drag(margin_left: i32, margin_top: i32, visual_width: f64) callconv(.c) void {
    _ = visual_width;
    var ox: f64 = 0;
    var oy: f64 = 0;
    if (native.wallify_panel_offsets(&ox, &oy)) {
        cached_offset_x = ox;
        cached_offset_y = oy;
        has_cached_offsets = true;
        return;
    }
    const player = playerWindowInfo();
    if (player.number > 0 and player.frame.size.width > 0 and player.frame.size.height > 0) {
        cached_offset_x = player.frame.origin.x - @as(f64, @floatFromInt(margin_left));
        cached_offset_y = player.frame.origin.y - @as(f64, @floatFromInt(margin_top));
        has_cached_offsets = true;
    }
}

/// Identifies active macOS desktop widgets and computes the closest grid snap position.
///
/// ## Desktop Widget Detection Strategy
/// Notification Center hosts desktop widgets, but without Screen Recording permissions macOS TCC
/// redacts `kCGWindowName` for foreign processes. We distinguish actual visible desktop widgets from
/// internal scratch surfaces (buffers, sidebars, alerts) using physical WindowServer properties:
/// 1. **Owner**: Owned by `Notification Center`.
/// 2. **Alpha**: Fully composited tiles have `alpha >= 0.5` (scratch caches linger at `0.0`).
/// 3. **Layer**: Live desktop widgets reside on the desktop layer (`-2147483601`).
/// 4. **Dimensions**: Size must be within plausible widget ranges (80pt to 1400pt).
pub export fn widget_nearby_panel_snap(margin_left: i32, margin_top: i32, visual_left: f64, visual_top: f64, visual_width: f64, visual_height: f64) callconv(.c) PanelSnap {
    var window_rects: [64]native.gpu.WallifyWindowRect = undefined;
    const candidate_count = wallify_desktop_candidates(&window_rects, window_rects.len);
    var candidates: [64]Rect = undefined;
    for (window_rects[0..candidate_count], 0..) |bounds, i| {
        candidates[i] = rect(bounds.x, bounds.y, bounds.width, bounds.height);
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

/// Pure geometric snap solver against detected widget candidate tiles.
/// Evaluates adjacent positions (above, below, left, and right) aligned to the 180pt grid pitch.
///
/// Multi-column widgets (e.g. 360pt wide Weather Forecast) and multi-column Wallify configurations
/// are evaluated per 180pt slot so widgets snap flush with uniform 16pt gutters.
///
/// The resulting outline is placed at the exact 164pt card position (target + 8pt) so the
/// outline preview matches the visible frosted card identically.
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
    var windows: [64]native.gpu.WallifyWindowRect = undefined;
    const count = @min(candidates.len, windows.len);
    for (candidates[0..count], 0..) |candidate, i| {
        windows[i] = .{ .x = candidate.origin.x, .y = candidate.origin.y, .width = candidate.size.width, .height = candidate.size.height };
    }
    var result: PanelSnap = undefined;
    wallify_calculate_panel_snap(&windows, count, visual_x, visual_y, visual_width, visual_height, offset_x, offset_y, visual_left, visual_top, &result);
    return result;
}

test "panel snap returns not found when candidates list is empty" {
    const snap = calculatePanelSnap(&.{}, 100, 100, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(!snap.found);
    try std.testing.expectEqual(@as(f64, 0), snap.distance_sq);
}

test "panel snap vertically aligns above/below neighboring widget" {
    const neighbor = rect(200, 300, 180, 180);
    const candidates = [_]Rect{neighbor};

    const snap_below = calculatePanelSnap(&candidates, 208, 495, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(snap_below.found);
    try std.testing.expectEqual(@as(f64, 488), snap_below.outline_y);
    try std.testing.expectEqual(@as(f64, 208), snap_below.outline_x);
    try std.testing.expectEqual(@as(f64, 164), snap_below.outline_width);
    try std.testing.expectEqual(@as(f64, 164), snap_below.outline_height);

    const snap_above = calculatePanelSnap(&candidates, 208, 125, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(snap_above.found);
    try std.testing.expectEqual(@as(f64, 128), snap_above.outline_y);
    try std.testing.expectEqual(@as(f64, 164), snap_above.outline_width);
    try std.testing.expectEqual(@as(f64, 164), snap_above.outline_height);
}

test "panel snap horizontally aligns to neighboring widget sides" {
    const neighbor = rect(400, 200, 180, 180);
    const candidates = [_]Rect{neighbor};

    const snap_right = calculatePanelSnap(&candidates, 590, 208, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(snap_right.found);
    try std.testing.expectEqual(@as(f64, 588), snap_right.outline_x);
    try std.testing.expectEqual(@as(f64, 208), snap_right.outline_y);
    try std.testing.expectEqual(@as(f64, 164), snap_right.outline_width);
    try std.testing.expectEqual(@as(f64, 164), snap_right.outline_height);

    const snap_left = calculatePanelSnap(&candidates, 225, 208, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(snap_left.found);
    try std.testing.expectEqual(@as(f64, 228), snap_left.outline_x);
}

test "expanded 3-column panel snap calculates 524x164 card preview" {
    const neighbor = rect(188, 221, 180, 180);
    const candidates = [_]Rect{neighbor};

    // Expanded panel is 540x180 (3 columns). Snapping right of neighbor at 188:
    const snap_right = calculatePanelSnap(&candidates, 370, 225, 540, 180, 0, 0, 0, 0);
    try std.testing.expect(snap_right.found);
    try std.testing.expectEqual(@as(f64, 376), snap_right.outline_x); // 188 + 180 + 8
    try std.testing.expectEqual(@as(f64, 229), snap_right.outline_y); // 221 + 8
    try std.testing.expectEqual(@as(f64, 524), snap_right.outline_width); // 540 - 16
    try std.testing.expectEqual(@as(f64, 164), snap_right.outline_height); // 180 - 16
}

test "panel snap preview matches every Wallify form factor card size" {
    const modes = [_]state.WidgetMode{
        .compact,
        .two_by_one,
        .expanded,
        .one_by_two,
        .two_by_two,
    };

    for (modes) |mode| {
        const size = mode.dimensions();
        const neighbor = rect(400, 400, 180, 180);
        const candidates = [_]Rect{neighbor};
        const result = calculatePanelSnap(
            &candidates,
            600,
            580,
            size.width,
            size.height,
            0,
            0,
            0,
            0,
        );

        try std.testing.expect(result.found);
        try std.testing.expectEqual(size.width - 16.0, result.outline_width);
        try std.testing.expectEqual(size.height - 16.0, result.outline_height);
    }
}

test "panel snap rejects candidates beyond distance threshold" {
    const neighbor = rect(2000, 2000, 180, 180);
    const candidates = [_]Rect{neighbor};
    const snap = calculatePanelSnap(&candidates, 100, 100, 180, 180, 0, 0, 0, 0);
    try std.testing.expect(!snap.found);
}

test "multi-column snapping preserves screen offsets and card inset" {
    const candidates = [_]Rect{rect(400, 400, 360, 360)};
    const result = calculatePanelSnap(&candidates, 225, 765, 540, 180, 10, 33, 8, 8);
    try std.testing.expect(result.found);
    try std.testing.expectEqual(@as(i32, 202), result.margin_left);
    try std.testing.expectEqual(@as(i32, 719), result.margin_top);
    try std.testing.expectEqual(@as(f64, 228), result.outline_x);
    try std.testing.expectEqual(@as(f64, 768), result.outline_y);
    try std.testing.expectEqual(@as(f64, 50), result.distance_sq);
    const invalid = calculatePanelSnap(&candidates, std.math.nan(f64), 765, 540, 180, 0, 0, 0, 0);
    try std.testing.expect(!invalid.found);
}
