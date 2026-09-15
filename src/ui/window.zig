const std = @import("std");
const macos = @import("../platform/macos.zig");

pub const snap = @import("snap.zig");

// Explicit snap re-exports for external callers
pub const PanelSnap = snap.PanelSnap;
pub const widget_start_drag = snap.widget_start_drag;
pub const widget_nearby_panel_snap = snap.widget_nearby_panel_snap;
pub const widget_show_snap_outline = snap.widget_show_snap_outline;
pub const widget_hide_snap_outline = snap.widget_hide_snap_outline;
pub const widget_set_snap_debug = snap.widget_set_snap_debug;
pub const widget_debug_window_show = snap.widget_debug_window_show;
pub const widget_debug_window_hide = snap.widget_debug_window_hide;
pub const calculatePanelSnap = snap.calculatePanelSnap;

// Application lifecycle and rendering synchronization
var render_mutex: std.atomic.Mutex = .unlocked;

pub export fn widget_render_lock() callconv(.c) void {
    while (!render_mutex.tryLock()) std.Thread.yield() catch {};
}

pub export fn widget_render_unlock() callconv(.c) void {
    render_mutex.unlock();
}

pub export fn widget_monotonic_time() callconv(.c) f64 {
    var now: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.MONOTONIC, &now);
    return @as(f64, @floatFromInt(now.sec)) + @as(f64, @floatFromInt(now.nsec)) / 1e9;
}

pub export fn widget_mouse_location() callconv(.c) macos.Point {
    return macos.send(macos.Point, macos.objc_getClass("NSEvent"), "mouseLocation", .{});
}

pub export fn widget_application_init() callconv(.c) void {
    const app = macos.send(macos.Ref, macos.objc_getClass("NSApplication"), "sharedApplication", .{});
    // NSApplicationActivationPolicyAccessory = 1 (accessory panel without dock icon)
    _ = macos.send(bool, app, "setActivationPolicy:", .{@as(isize, 1)});
}

pub export fn widget_application_run() callconv(.c) void {
    const app = macos.send(macos.Ref, macos.objc_getClass("NSApplication"), "sharedApplication", .{});
    macos.send(void, app, "run", .{});
}
