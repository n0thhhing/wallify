const std = @import("std");
const state = @import("state.zig");
const macos = @import("macos.zig");
const input = @import("ui/input.zig");
const animation = @import("graphics/animation.zig");
const media = @import("media/media.zig");
const render = @import("graphics/render.zig");

pub fn main() !void {
    state.desktop_mode = std.c.getenv("WALLIFY_DESKTOP") != null;
    // Gives the panel a stable identity in CGWindowList, used when finding
    // desktop-widget neighbors while it is being dragged.
    std.debug.print("\x1b]2;spotify-player\x07", .{});
    macos.widget_application_init();
    state.loadWidgetSettings();
    state.mode_mix = @floatFromInt(state.setting_mode);
    macos.widget_spotify_observe();
    try input.enableRawMode();

    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    std.debug.print("\x1b[2J\x1b[H", .{});
    state.requestFrame();

    render.drawUIFrame();
    const t = try std.Thread.spawn(.{}, input.inputLoop, .{});
    t.detach();
    const anim = try std.Thread.spawn(.{}, animation.animationLoop, .{});
    anim.detach();
    const metadata = try std.Thread.spawn(.{}, media.metadataLoop, .{io});
    metadata.detach();

    macos.widget_application_run();
}
