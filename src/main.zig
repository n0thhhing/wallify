const std = @import("std");
const state = @import("state.zig");
const input = @import("ui/input.zig");
const animation = @import("graphics/animation.zig");
const media = @import("media/controller.zig");
const render = @import("graphics/render.zig");
const window = @import("ui/window.zig");
const spotify = @import("media/spotify.zig");

fn handleSignal(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    const reset_seq = "\x1b_Ga=d,d=A\x1b\\\x1b[?1016l\x1b[?1003l\x1b[?1006l\x1b[?25h\n";
    _ = std.c.write(1, reset_seq.ptr, reset_seq.len);
    std.c._exit(0);
}

pub fn main() !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = 0,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
    std.posix.sigaction(std.posix.SIG.HUP, &act, null);

    state.desktop_mode = std.c.getenv("WALLIFY_DESKTOP") != null;
    // Gives the panel a stable identity in CGWindowList, used when finding
    // desktop-widget neighbors while it is being dragged.
    std.debug.print("\x1b]2;spotify-player\x07", .{});
    window.widget_application_init();
    state.loadWidgetSettings();
    if (state.setting_debug) window.widget_debug_window_show();
    state.mode_mix = @floatFromInt(@intFromEnum(state.setting_mode));
    spotify.widget_spotify_observe();
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

    window.widget_application_run();
}

test {
    _ = @import("state.zig");
    _ = @import("graphics/pets/idle_cat.zig");
    _ = @import("ui/context_menu.zig");
    _ = @import("ui/hitbox.zig");
    _ = @import("ui/window.zig");
    _ = @import("media/playback_state.zig");
    _ = @import("media/playback_clock.zig");
    _ = @import("media/controller.zig");
    _ = @import("media/spotify.zig");
    _ = @import("graphics/icon_transition.zig");
    _ = @import("graphics/pixel_engine.zig");
}
