const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const input = @import("ui/input.zig");
const animation = @import("graphics/animation.zig");
const media = @import("media/controller.zig");
const render = @import("graphics/render.zig");
const window = @import("ui/window.zig");
const spotify = @import("media/spotify.zig");
const build_options = @import("build_options");

extern fn wallify_imgui_inspector_show() void;
extern fn wallify_debug_console_install() void;
pub const settings_window = @import("ui/settings_window.zig");

pub fn main() !void {
    if (builtin.mode == .Debug) {
        wallify_debug_console_install();
        std.log.info("startup: Debug build, inspector={s}, profiling={s}", .{
            if (build_options.debug_inspector) "enabled" else "disabled",
            if (std.c.getenv("WALLIFY_PROFILE") != null) "on" else "off",
        });
    }
    @import("platform/native.zig").wallify_prepare();
    window.widget_application_init();
    state.loadWidgetSettings();
    std.log.info("startup: settings loaded, mode={s}, source={s}, position={d},{d}", .{
        @tagName(state.setting_mode),
        @tagName(state.setting_source),
        state.widget_margin_left,
        state.widget_margin_top,
    });
    if (state.setting_debug) window.widget_debug_window_show();
    const initial_size = state.setting_mode.dimensions();
    state.mode_from = state.setting_mode;
    state.mode_mix = 1.0;
    state.mode_transition_active = false;
    state.mode_start_width = initial_size.width;
    state.mode_start_height = initial_size.height;
    state.mode_target_width = initial_size.width;
    state.mode_target_height = initial_size.height;
    spotify.widget_spotify_observe();
    if (!@import("platform/native.zig").create(state.setting_mode, state.widget_margin_left, state.widget_margin_top)) return error.MetalUnavailable;
    std.log.info("startup: widget created at {d},{d}, dimensions={d}x{d}", .{
        state.widget_margin_left,
        state.widget_margin_top,
        @as(i32, @intFromFloat(initial_size.width)),
        @as(i32, @intFromFloat(initial_size.height)),
    });
    if (build_options.debug_inspector and builtin.mode == .Debug) wallify_imgui_inspector_show();

    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const open_settings_on_launch = @import("platform/native.zig").wallify_has_settings_flag();

    state.requestFrame();

    render.drawUIFrame();
    _ = &input.wallify_pointer;
    media.ensureWorkerStarted();
    const anim = try std.Thread.spawn(.{}, animation.animationLoop, .{});
    anim.detach();
    const metadata = try std.Thread.spawn(.{}, media.metadataLoop, .{io});
    metadata.detach();

    if (open_settings_on_launch) {
        settings_window.open();
    }

    window.widget_application_run();
}

test {
    _ = &input.wallify_pointer;
    _ = @import("graphics/canvas.zig");
    _ = @import("graphics/render/idle.zig");
    _ = @import("graphics/render/player.zig");
    _ = @import("state.zig");
    _ = @import("settings.zig");
    _ = @import("graphics/pets/idle_cat.zig");
    _ = @import("ui/layout.zig");
    _ = @import("ui/snap.zig");
    _ = @import("ui/hitbox.zig");
    _ = @import("ui/window.zig");
    _ = @import("ui/settings_window.zig");
    _ = @import("media/playback_state.zig");
    _ = @import("media/playback_clock.zig");
    _ = @import("media/controller.zig");
    _ = @import("media/spotify.zig");
    _ = @import("graphics/icon_transition.zig");
    _ = @import("graphics/assets.zig");
    _ = @import("graphics/sprites.zig");
}
