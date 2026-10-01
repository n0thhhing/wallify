const std = @import("std");

pub const ContextMenuAction = enum(c_int) {
    none = 0,
    play_pause = 1,
    previous_track = 2,
    next_track = 3,
    open_spotify = 4,
    toggle_glow = 5,
    toggle_aurora = 6,
    toggle_animations = 7,
    toggle_dim = 8,
    frame_off = 10,
    frame_subtle = 11,
    frame_strong = 12,
    intensity_low = 20,
    intensity_normal = 21,
    intensity_high = 22,
    speed_slow = 30,
    speed_normal = 31,
    speed_fast = 32,
    restore_defaults = 40,
    source_now_playing = 50,
    source_spotify = 51,
    source_spotifast = 52,
    mode_compact = 60,
    mode_two_by_one = 61,
    mode_expanded = 62,
    mode_one_by_two = 63,
    mode_two_by_two = 64,
    transition_default = 70,
    transition_cinematic = 71,
    transition_ripple = 72,
    transition_flip = 73,
    transition_vinyl = 74,
    transition_glitch = 75,
    idle_spotify = 80,
    idle_pixel = 81,
    idle_banana = 82,
    idle_raccoon = 83,
    open_settings = 90,
    _,
};

extern fn wallify_native_menu_selected(tag: c_int) callconv(.c) void;
extern fn wallify_native_menu_action() callconv(.c) c_int;
extern fn wallify_show_context_menu() callconv(.c) void;
pub fn widget_context_menu() void {
    wallify_show_context_menu();
}
pub export fn wallify_context_menu_selected(tag: c_int) callconv(.c) void {
    wallify_native_menu_selected(tag);
}
pub export fn widget_context_menu_action() callconv(.c) ContextMenuAction {
    return @enumFromInt(wallify_native_menu_action());
}

test "context menu action tags stay stable" {
    const expected = [_]struct { tag: c_int, action: ContextMenuAction }{
        .{ .tag = 1, .action = .play_pause },
        .{ .tag = 2, .action = .previous_track },
        .{ .tag = 3, .action = .next_track },
        .{ .tag = 4, .action = .open_spotify },
        .{ .tag = 50, .action = .source_now_playing },
        .{ .tag = 51, .action = .source_spotify },
        .{ .tag = 52, .action = .source_spotifast },
        .{ .tag = 60, .action = .mode_compact },
        .{ .tag = 61, .action = .mode_two_by_one },
        .{ .tag = 62, .action = .mode_expanded },
        .{ .tag = 63, .action = .mode_one_by_two },
        .{ .tag = 64, .action = .mode_two_by_two },
        .{ .tag = 90, .action = .open_settings },
    };

    for (expected) |item| {
        try std.testing.expectEqual(item.action, @as(ContextMenuAction, @enumFromInt(item.tag)));
    }
}

test "context menu selection is consumed once" {
    wallify_context_menu_selected(83);
    try std.testing.expectEqual(ContextMenuAction.idle_raccoon, widget_context_menu_action());
    try std.testing.expectEqual(ContextMenuAction.none, widget_context_menu_action());
}
