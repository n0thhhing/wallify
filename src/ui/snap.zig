const std = @import("std");
const macos = @import("../platform/macos.zig");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");

const Ref = macos.Ref;
const Point = macos.Point;
const Rect = macos.Rect;
const rect = macos.rect;

// Grid metrics & snap tuning
// macOS Sequoia arranges small desktop widgets in 180×180pt tiles.
const GRID_PITCH: f64 = state.Layout.grid_pitch;
const SNAP_THRESHOLD: f64 = 1100.0 * 1100.0;
const MAX_CANDIDATE_WIDTH: f64 = 1400.0;
const MAX_CANDIDATE_HEIGHT: f64 = 800.0;
const MIN_CANDIDATE_SIZE: f64 = 80.0;
const OUTLINE_RADIUS: f64 = state.Layout.card_radius;
const DEBUG_PANEL_LEVEL: isize = 101;
const DEBUG_PANEL_WIDTH: f64 = 680.0;
const DEBUG_PANEL_HEIGHT: f64 = 600.0;
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
var snap_debug_header: Ref = null;
var snap_debug_footer: Ref = null;
var snap_debug_panes: [6]Ref = .{ null, null, null, null, null, null };
var snap_debug_target: Ref = null;
var snap_debug_controls: [18]Ref = .{ null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null };
var snap_debug_readouts: [8]Ref = .{ null, null, null, null, null, null, null, null };
var snap_debug_tick: u64 = 0;
var snap_outline_was_visible = false;
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

fn stringEquals(value: Ref, expected: []const u8) bool {
    if (value == null) return false;
    var buffer: [128]u8 = undefined;
    if (macos.CFStringGetCString(value, &buffer, buffer.len, 0x08000100) == 0) return false;
    return std.ascii.eqlIgnoreCase(std.mem.sliceTo(&buffer, 0), expected);
}

fn isPlayerWindow(info: Ref) bool {
    const name = macos.CFDictionaryGetValue(info, macos.kCGWindowName);
    if (name) |n| {
        if (stringEquals(n, "Wallify Debug Console") or
            stringEquals(n, "Wallify Snap Outline") or
            stringEquals(n, "Wallify Settings")) return false;
    }

    const expected_id = native.wallify_panel_window_number();
    if (expected_id > 0) {
        if (macos.CFDictionaryGetValue(info, macos.kCGWindowNumber)) |num_ref| {
            var win_id: i64 = 0;
            if (macos.CFNumberGetValue(num_ref, 4, @ptrCast(&win_id))) {
                return win_id == @as(i64, @intCast(expected_id));
            }
        }
    }

    const owner = macos.CFDictionaryGetValue(info, macos.kCGWindowOwnerName);
    const matches = stringEquals(name, "Wallify") or stringEquals(owner, "Wallify");
    if (!matches) return false;

    if (name) |n| {
        if (!stringEquals(n, "Wallify")) return false;
    }

    var layer: i64 = 0;
    if (macos.CFDictionaryGetValue(info, macos.kCGWindowLayer)) |layer_ref| {
        _ = macos.CFNumberGetValue(layer_ref, 4, @ptrCast(&layer));
    }
    return layer == -1;
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

fn setInspectorText(label: Ref, value: []const u8) void {
    const ns_value = macos.string(value);
    defer macos.CFRelease(ns_value);
    macos.send(void, label, "setStringValue:", .{ns_value});
}

fn makeInspectorPage(title_text: []const u8) Ref {
    const view = macos.send(
        Ref,
        macos.send(Ref, macos.objc_getClass("NSView"), "alloc", .{}),
        "initWithFrame:",
        .{rect(0, 0, DEBUG_PANEL_WIDTH, DEBUG_PANEL_HEIGHT - 44.0)},
    );
    if (view == null) return null;

    macos.send(void, view, "setWantsLayer:", .{true});
    const layer = macos.send(Ref, view, "layer", .{});
    if (layer != null) {
        const background = macos.send(
            Ref,
            macos.objc_getClass("NSColor"),
            "colorWithCalibratedWhite:alpha:",
            .{@as(f64, 0.075), @as(f64, 1.0)},
        );
        macos.send(void, layer, "setBackgroundColor:", .{macos.send(Ref, background, "CGColor", .{})});
    }

    const label_cls = macos.objc_getClass("NSTextField");
    const title = macos.send(
        Ref,
        macos.send(Ref, label_cls, "alloc", .{}),
        "initWithFrame:",
        .{rect(18, DEBUG_PANEL_HEIGHT - 76.0, DEBUG_PANEL_WIDTH - 36.0, 22.0)},
    );
    if (title == null) return null;
    macos.send(void, title, "setEditable:", .{false});
    macos.send(void, title, "setSelectable:", .{false});
    macos.send(void, title, "setBezeled:", .{false});
    macos.send(void, title, "setDrawsBackground:", .{false});
    const title_font = macos.send(
        Ref,
        macos.objc_getClass("NSFont"),
        "systemFontOfSize:weight:",
        .{@as(f64, 18.0), @as(f64, 0.65)},
    );
    if (title_font != null) macos.send(void, title, "setFont:", .{title_font});
    const title_color = macos.send(
        Ref,
        macos.objc_getClass("NSColor"),
        "colorWithCalibratedWhite:alpha:",
        .{@as(f64, 0.92), @as(f64, 1.0)},
    );
    macos.send(void, title, "setTextColor:", .{title_color});
    const title_value = macos.string(title_text);
    defer macos.CFRelease(title_value);
    macos.send(void, title, "setStringValue:", .{title_value});
    macos.send(void, title, "setAutoresizingMask:", .{@as(usize, 2 | 8)});
    macos.send(void, view, "addSubview:", .{title});

    const body = macos.send(
        Ref,
        macos.send(Ref, label_cls, "alloc", .{}),
        "initWithFrame:",
        .{rect(18, 18, DEBUG_PANEL_WIDTH - 36.0, DEBUG_PANEL_HEIGHT - 108.0)},
    );
    if (body == null) return null;
    macos.send(void, body, "setEditable:", .{false});
    macos.send(void, body, "setSelectable:", .{true});
    macos.send(void, body, "setBezeled:", .{false});
    macos.send(void, body, "setDrawsBackground:", .{false});
    macos.send(void, body, "setUsesSingleLineMode:", .{false});
    macos.send(void, body, "setLineBreakMode:", .{@as(isize, 0)});
    const body_font = macos.send(
        Ref,
        macos.objc_getClass("NSFont"),
        "monospacedSystemFontOfSize:weight:",
        .{@as(f64, 12.0), @as(f64, 0.0)},
    );
    if (body_font != null) macos.send(void, body, "setFont:", .{body_font});
    const body_color = macos.send(
        Ref,
        macos.objc_getClass("NSColor"),
        "colorWithCalibratedWhite:alpha:",
        .{@as(f64, 0.78), @as(f64, 1.0)},
    );
    macos.send(void, body, "setTextColor:", .{body_color});
    macos.send(void, body, "setAutoresizingMask:", .{@as(usize, 2 | 16)});
    macos.send(void, view, "addSubview:", .{body});

    return view;
}

fn updateInspectorPage(view: Ref, value: []const u8) void {
    if (view == null) return;
    const subviews = macos.send(Ref, view, "subviews", .{});
    if (subviews == null) return;
    const count = macos.CFArrayGetCount(subviews);
    if (count < 2) return;
    const body = macos.CFArrayGetValueAtIndex(subviews, 1);
    setInspectorText(body, value);
}

fn updateSnapDebug() void {
    if (!state.setting_debug) {
        if (snap_debug_panel) |panel| macos.send(void, panel, "orderOut:", .{@as(Ref, null)});
        return;
    }

    if (snap_debug_panel == null) {
        const panel_cls = macos.objc_getClass("NSPanel");
        const panel = macos.send(
            Ref,
            macos.send(Ref, panel_cls, "alloc", .{}),
            "initWithContentRect:styleMask:backing:defer:",
            .{
                rect(24, 60, DEBUG_PANEL_WIDTH, DEBUG_PANEL_HEIGHT),
                @as(usize, 1 | 2 | 32),
                @as(usize, 2),
                false,
            },
        );
        if (panel == null) return;
        snap_debug_panel = panel;

        const title = macos.string("Wallify Inspector");
        defer macos.CFRelease(title);
        macos.send(void, panel, "setTitle:", .{title});
        macos.send(void, panel, "setFloatingPanel:", .{true});
        macos.send(void, panel, "setOpaque:", .{true});
        const bg = macos.send(
            Ref,
            macos.objc_getClass("NSColor"),
            "colorWithCalibratedWhite:alpha:",
            .{@as(f64, 0.065), @as(f64, 1.0)},
        );
        macos.send(void, panel, "setBackgroundColor:", .{bg});
        macos.send(void, panel, "setLevel:", .{@as(isize, DEBUG_PANEL_LEVEL)});
        macos.send(void, panel, "setHidesOnDeactivate:", .{false});
        macos.send(void, panel, "setReleasedWhenClosed:", .{false});

        const content = macos.send(Ref, panel, "contentView", .{});
        if (content == null) return;

        const tab_cls = macos.objc_getClass("NSTabView");
        const tabs = macos.send(
            Ref,
            macos.send(Ref, tab_cls, "alloc", .{}),
            "initWithFrame:",
            .{rect(0, 0, DEBUG_PANEL_WIDTH, DEBUG_PANEL_HEIGHT - 26.0)},
        );
        if (tabs == null) return;
        macos.send(void, tabs, "setTabViewType:", .{@as(usize, 0)});
        macos.send(void, tabs, "setAutoresizingMask:", .{@as(usize, 18)});
        macos.send(void, content, "addSubview:", .{tabs});

        const item_cls = macos.objc_getClass("NSTabViewItem");
        const titles = [_][]const u8{
            "Runtime",
            "Appearance",
            "Media",
            "Window",
            "WindowServer",
            "Snap",
        };

        for (titles, 0..) |tab_title, i| {
            const item = macos.send(
                Ref,
                macos.send(Ref, item_cls, "alloc", .{}),
                "initWithIdentifier:",
                .{macos.string(tab_title)},
            );
            if (item == null) continue;
            defer macos.CFRelease(macos.send(Ref, item, "identifier", .{}));
            const label_value = macos.string(tab_title);
            defer macos.CFRelease(label_value);
            macos.send(void, item, "setLabel:", .{label_value});

            const page = makeInspectorPage(tab_title);
            if (page == null) continue;
            macos.send(void, item, "setView:", .{page});
            macos.send(void, tabs, "addTabViewItem:", .{item});
            snap_debug_panes[i] = page;
        }

        macos.send(void, tabs, "selectFirstTabViewItem:", .{@as(Ref, null)});

        const footer_cls = macos.objc_getClass("NSTextField");
        const footer = macos.send(
            Ref,
            macos.send(Ref, footer_cls, "alloc", .{}),
            "initWithFrame:",
            .{rect(16, 7, DEBUG_PANEL_WIDTH - 32.0, 16.0)},
        );
        if (footer != null) {
            snap_debug_footer = footer;
            macos.send(void, footer, "setEditable:", .{false});
            macos.send(void, footer, "setSelectable:", .{false});
            macos.send(void, footer, "setBezeled:", .{false});
            macos.send(void, footer, "setDrawsBackground:", .{false});
            const font = macos.send(Ref, macos.objc_getClass("NSFont"), "systemFontOfSize:", .{@as(f64, 10.0)});
            if (font != null) macos.send(void, footer, "setFont:", .{font});
            const color = macos.send(
                Ref,
                macos.objc_getClass("NSColor"),
                "colorWithCalibratedWhite:alpha:",
                .{@as(f64, 0.46), @as(f64, 1.0)},
            );
            macos.send(void, footer, "setTextColor:", .{color});
            macos.send(void, content, "addSubview:", .{footer});
        }
    }

    const actual = if (snap_outline) |panel| macos.send(Rect, panel, "frame", .{}) else rect(0, 0, 0, 0);
    const outline_number = if (snap_outline) |value| macos.send(isize, value, "windowNumber", .{}) else 0;
    const outline_level = if (snap_outline) |value| macos.send(isize, value, "level", .{}) else 0;
    const player = playerWindowInfo();
    const screen = macos.send(Ref, macos.objc_getClass("NSScreen"), "mainScreen", .{}) orelse return;
    const screen_frame = macos.send(Rect, screen, "frame", .{});

    snap_debug_tick += 1;

    var runtime: [1024]u8 = undefined;
    const runtime_text = std.fmt.bufPrint(
        &runtime,
        "Playback       {s} — {s}\n" ++
            "Time           {d:.1}s / {d:.1}s\n" ++
            "Artwork        {s}\n" ++
            "Mode           {d}\n" ++
            "Mode mix       {d:.3}\n" ++
            "Render size    {d:.0} × {d:.0}\n" ++
            "Dragging       {s}\n\n" ++
            "State          {s}",
        .{
            state.global_title[0..state.global_title_len],
            state.global_artist[0..state.global_artist_len],
            state.global_elapsed,
            state.global_duration,
            if (state.global_has_artwork) "yes" else "no",
            @intFromEnum(state.setting_mode),
            snap_debug_mode_mix,
            snap_debug_card_width,
            snap_debug_card_height,
            if (snap_debug_dragging) "true" else "false",
            if (snap_debug_dragging) "moving" else "idle",
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[0], runtime_text);

    var appearance: [512]u8 = undefined;
    const appearance_text = std.fmt.bufPrint(
        &appearance,
        "Native glass   {s}\nGlow           {s}\nAurora         {s}\nAnimations     {s}\nAnimation speed {d}",
        .{
            if (state.setting_native_glass) "on" else "off",
            if (state.setting_glow) "on" else "off",
            if (state.setting_aurora) "on" else "off",
            if (state.setting_animations) "on" else "off",
            @intFromEnum(state.setting_speed),
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[1], appearance_text);

    var media: [1024]u8 = undefined;
    const media_text = std.fmt.bufPrint(
        &media,
        "Source         {d}\nTransition     {d}\nArtwork        {s}\nTitle          {s}\nArtist         {s}",
        .{
            @intFromEnum(state.setting_source),
            @intFromEnum(state.setting_transition),
            if (state.global_has_artwork) "available" else "none",
            state.global_title[0..state.global_title_len],
            state.global_artist[0..state.global_artist_len],
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[2], media_text);

    var window: [1024]u8 = undefined;
    const window_text = std.fmt.bufPrint(
        &window,
        "Wallify id     #{d}\nLayer          {d}\nScreen         {d:.0} × {d:.0}\nMargin         {d:.0}, {d:.0}\nVisual         {d:.0}, {d:.0}\nPanel frame    {d:.0}, {d:.0}  {d:.0} × {d:.0}",
        .{
            player.number,
            player.layer,
            screen_frame.size.width,
            screen_frame.size.height,
            snap_last_margin.x,
            snap_last_margin.y,
            snap_last_visual.x,
            snap_last_visual.y,
            actual.origin.x,
            actual.origin.y,
            actual.size.width,
            actual.size.height,
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[3], window_text);

    var window_server: [1024]u8 = undefined;
    const ws_text = std.fmt.bufPrint(
        &window_server,
        "Candidates     {d}\nOutline        {s}\nDistance²      {d:.0}\nOutline id     #{d}\nOutline level  {d}\nCache offset   {d:.0}, {d:.0}\nCache valid    {s}",
        .{
            snap_candidate_count,
            if (snap_outline != null and macos.send(bool, snap_outline, "isVisible", .{})) "visible" else "hidden",
            snap_last_distance_sq,
            outline_number,
            outline_level,
            cached_offset_x,
            cached_offset_y,
            if (has_cached_offsets) "true" else "false",
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[4], ws_text);

    var snap: [1024]u8 = undefined;
    const snap_text = std.fmt.bufPrint(
        &snap,
        "Target         {d:.0}, {d:.0}\nTarget size    {d:.0} × {d:.0}\nThreshold²     {d:.0}\nSnap state     {s}\nOutline rect   {d:.0}, {d:.0}  {d:.0} × {d:.0}",
        .{
            snap_outline_rect.origin.x,
            snap_outline_rect.origin.y,
            snap_outline_rect.size.width,
            snap_outline_rect.size.height,
            SNAP_THRESHOLD,
            if (snap_candidate_count > 0) "candidates detected" else "no candidates",
            snap_outline_rect.origin.x,
            snap_outline_rect.origin.y,
            snap_outline_rect.size.width,
            snap_outline_rect.size.height,
        },
    ) catch return;
    updateInspectorPage(snap_debug_panes[5], snap_text);

    if (snap_debug_footer) |footer| {
        var status: [192]u8 = undefined;
        const status_text = std.fmt.bufPrint(
            &status,
            "LIVE   tick {d}   •   candidates {d}   •   outline {s}   •   cache {s}",
            .{
                snap_debug_tick,
                snap_candidate_count,
                if (snap_outline != null and macos.send(bool, snap_outline, "isVisible", .{})) "visible" else "hidden",
                if (has_cached_offsets) "valid" else "uncached",
            },
        ) catch return;
        const footer_value = macos.string(status_text);
        defer macos.CFRelease(footer_value);
        macos.send(void, footer, "setStringValue:", .{footer_value});
    }

    if (!macos.send(bool, snap_debug_panel, "isVisible", .{})) {
        macos.send(void, snap_debug_panel, "setAlphaValue:", .{@as(f64, 0)});
        macos.send(void, snap_debug_panel, "orderFrontRegardless", .{});
        macos.send(void, macos.send(Ref, snap_debug_panel, "animator", .{}), "setAlphaValue:", .{@as(f64, 1)});
    } else {
        macos.send(void, snap_debug_panel, "orderFrontRegardless", .{});
    }
}

fn updateSnapOutline(_: Ref) callconv(.c) void {
    const screen = macos.send(Ref, macos.objc_getClass("NSScreen"), "mainScreen", .{}) orelse return;
    const screen_frame = macos.send(Rect, screen, "frame", .{});
    const preview_rect = snap_outline_rect;
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
        const title = macos.string("Wallify Snap Outline");
        defer macos.CFRelease(title);
        macos.send(void, panel, "setTitle:", .{title});
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
        macos.send(void, view, "setAutoresizingMask:", .{@as(usize, 18)});
        const layer = macos.send(Ref, view, "layer", .{});
        macos.send(void, layer, "setMasksToBounds:", .{true});
        macos.send(void, layer, "setCornerRadius:", .{@as(f64, OUTLINE_RADIUS)});
        macos.send(void, layer, "setBorderWidth:", .{@as(f64, 2.5)});
        const rim = macos.send(Ref, macos.send(Ref, macos.objc_getClass("NSColor"), "whiteColor", .{}), "colorWithAlphaComponent:", .{@as(f64, 0.45)});
        macos.send(void, layer, "setBorderColor:", .{macos.send(Ref, rim, "CGColor", .{})});
        const bg = macos.send(Ref, macos.send(Ref, macos.objc_getClass("NSColor"), "whiteColor", .{}), "colorWithAlphaComponent:", .{@as(f64, 0.08)});
        macos.send(void, layer, "setBackgroundColor:", .{macos.send(Ref, bg, "CGColor", .{})});
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
    const layer = macos.send(Ref, content, "layer", .{});
    if (layer != null) macos.send(void, layer, "setFrame:", .{rect(0, 0, frame.size.width, frame.size.height)});
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
    var ox: f64 = 0;
    var oy: f64 = 0;
    if (native.wallify_panel_offsets(&ox, &oy)) {
        cached_offset_x = ox;
        cached_offset_y = oy;
        has_cached_offsets = true;
        return;
    }
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
    const grid_pitch: f64 = GRID_PITCH;
    const threshold_sq: f64 = SNAP_THRESHOLD;
    var best_dist = threshold_sq;
    var result = PanelSnap{};
    const player_columns: i32 = @max(1, @as(i32, @intFromFloat(@round(visual_width / grid_pitch))));

    for (candidates) |neighbor| {
        var col: i32 = 0;
        const columns: i32 = @max(1, @as(i32, @intFromFloat(@round(neighbor.size.width / grid_pitch))));
        const rows: i32 = @max(1, @as(i32, @intFromFloat(@round(neighbor.size.height / grid_pitch))));
        while (col < columns) : (col += 1) {
            const cell_x = neighbor.origin.x + @as(f64, @floatFromInt(col)) * grid_pitch;
            var player_col: i32 = 0;
            while (player_col < player_columns) : (player_col += 1) {
                const aligned_left = cell_x - @as(f64, @floatFromInt(player_col)) * grid_pitch;
                const targets = [_]Point{
                    .{ .x = aligned_left, .y = neighbor.origin.y - visual_height },
                    .{ .x = aligned_left, .y = neighbor.origin.y + neighbor.size.height },
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
                            .outline_x = target.x + 8.0,
                            .outline_y = target.y + 8.0,
                            .outline_width = visual_width - 16.0,
                            .outline_height = visual_height - 16.0,
                            .distance_sq = dist_sq,
                        };
                    }
                }
            }
        }
        var row: i32 = 0;
        while (row < rows) : (row += 1) {
            const aligned_top = neighbor.origin.y + @as(f64, @floatFromInt(row)) * grid_pitch;
            const side_targets = [_]Point{
                .{ .x = neighbor.origin.x - visual_width, .y = aligned_top },
                .{ .x = neighbor.origin.x + neighbor.size.width, .y = aligned_top },
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
                        .outline_x = target.x + 8.0,
                        .outline_y = target.y + 8.0,
                        .outline_width = visual_width - 16.0,
                        .outline_height = visual_height - 16.0,
                        .distance_sq = distance,
                    };
                }
            }
        }
    }
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

test "isPlayerWindow rejects settings and debug windows" {
    // Construct mock CFDictionary for Wallify Settings
    const name_key = macos.kCGWindowName;
    const owner_key = macos.kCGWindowOwnerName;
    const layer_key = macos.kCGWindowLayer;

    // Create a dictionary for Wallify Settings (owner: Wallify, name: Wallify Settings, layer: 3)
    const dict_cls = macos.objc_getClass("NSMutableDictionary");
    const dict = macos.send(macos.Ref, macos.send(macos.Ref, dict_cls, "alloc", .{}), "init", .{});
    defer macos.CFRelease(dict);

    const owner_val = macos.string("Wallify");
    defer macos.CFRelease(owner_val);
    const name_settings = macos.string("Wallify Settings");
    defer macos.CFRelease(name_settings);
    const num_cls = macos.objc_getClass("NSNumber");
    const layer_val = macos.send(macos.Ref, num_cls, "numberWithInt:", .{@as(c_int, 3)});

    macos.send(void, dict, "setObject:forKey:", .{ owner_val, owner_key });
    macos.send(void, dict, "setObject:forKey:", .{ name_settings, name_key });
    macos.send(void, dict, "setObject:forKey:", .{ layer_val, layer_key });

    try std.testing.expect(!isPlayerWindow(dict));

    // Now change name to Wallify and layer to -1 (the actual widget panel)
    const name_widget = macos.string("Wallify");
    defer macos.CFRelease(name_widget);
    const widget_layer = macos.send(macos.Ref, num_cls, "numberWithInt:", .{@as(c_int, -1)});
    macos.send(void, dict, "setObject:forKey:", .{ name_widget, name_key });
    macos.send(void, dict, "setObject:forKey:", .{ widget_layer, layer_key });

    try std.testing.expect(isPlayerWindow(dict));
}
