const std = @import("std");
const state = @import("../state.zig");
const macos = @import("../platform/macos.zig");

pub const ContextMenuAction = enum(c_int) {
    none = 0,
    play_pause = 1,
    previous_track = 2,
    next_track = 3,
    open_spotify = 4,
    toggle_glow = 5,
    toggle_animations = 6,
    toggle_dim = 7,
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
    mode_compact = 60,
    mode_expanded = 61,
    idle_spotify = 80,
    idle_pixel = 81,
    idle_banana = 82,
    _,
};

var menu_action: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(0);
var menu_open: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn chooseCallback(_: macos.Ref, _: macos.Ref, sender: macos.Ref) callconv(.c) void {
    const tag = macos.send0(isize, sender, "tag");
    menu_action.store(@intCast(tag), .monotonic);
}

fn getMenuTarget() macos.Ref {
    const TargetHolder = struct {
        var instance: macos.Ref = null;
        var once: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
        fn get() macos.Ref {
            if (!once.swap(true, .monotonic)) {
                const superclass = macos.objc_getClass("NSObject");
                const cls = macos.objc_allocateClassPair(superclass, "WallifyMenuTarget", 0);
                if (cls != null) {
                    _ = macos.class_addMethod(cls, macos.sel_registerName("choose:"), @ptrCast(&chooseCallback), "v@:@");
                    macos.objc_registerClassPair(cls);
                    instance = macos.send0(macos.Ref, macos.send0(macos.Ref, cls, "alloc"), "init");
                }
            }
            return instance;
        }
    };
    return TargetHolder.get();
}

pub export fn widget_context_menu_action() callconv(.c) ContextMenuAction {
    return @enumFromInt(menu_action.swap(0, .monotonic));
}

pub const ContextMenuCtx = struct {
    playing: c_int,
    glow: c_int,
    animations: c_int,
    dim: c_int,
    frame: state.FrameStrength,
    intensity: state.GlowIntensity,
    speed: state.AnimationSpeed,
    source: state.MediaSource,
    mode: state.WidgetMode,

    fn show(ctx_ptr: macos.Ref) callconv(.c) void {
        const self: *ContextMenuCtx = @ptrCast(@alignCast(ctx_ptr));
        defer std.heap.c_allocator.destroy(self);

        const ns_app = macos.send0(macos.Ref, macos.objc_getClass("NSApplication"), "sharedApplication");
        const ns_ws = macos.send0(macos.Ref, macos.objc_getClass("NSWorkspace"), "sharedWorkspace");
        const previous_app = macos.send0(macos.Ref, ns_ws, "frontmostApplication");
        const location = macos.send0(macos.Point, macos.objc_getClass("NSEvent"), "mouseLocation");

        _ = macos.send1(bool, ns_app, "activateIgnoringOtherApps:", bool, true);

        const pool = macos.send0(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc"), "init");
        defer macos.send0(void, pool, "release");

        const target = getMenuTarget();
        const menu_cls = macos.objc_getClass("NSMenu");
        const item_cls = macos.objc_getClass("NSMenuItem");

        const title_str = macos.string("Wallify");
        defer macos.CFRelease(title_str);
        const menu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, title_str);
        macos.send1(void, menu, "setAutoenablesItems:", bool, false);

        const empty_str = macos.string("");
        defer macos.CFRelease(empty_str);

        const main_labels = [_][]const u8{
            if (self.playing != 0) "Pause" else "Play",
            "Previous Track",
            "Next Track",
            "Open Spotify",
        };

        const choose_sel = macos.sel_registerName("choose:");

        for (main_labels, 0..) |lbl, i| {
            const s = macos.string(lbl);
            defer macos.CFRelease(s);
            const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, s, macos.Ref, choose_sel, macos.Ref, empty_str);
            macos.send1(void, item, "setTarget:", macos.Ref, target);
            macos.send1(void, item, "setTag:", isize, @intCast(i + 1));
            macos.send1(void, menu, "addItem:", macos.Ref, item);
        }

        macos.send1(void, menu, "addItem:", macos.Ref, macos.send0(macos.Ref, item_cls, "separatorItem"));

        const source_title = macos.string("Media Source");
        defer macos.CFRelease(source_title);
        const source_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, source_title, macos.Ref, null, macos.Ref, empty_str);
        const source_submenu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, source_title);
        macos.send1(void, source_submenu, "setAutoenablesItems:", bool, false);

        const sources = [_][]const u8{ "Now Playing", "Spotify" };
        for (sources, 0..) |src_name, i| {
            const s = macos.string(src_name);
            defer macos.CFRelease(s);
            const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, s, macos.Ref, choose_sel, macos.Ref, empty_str);
            macos.send1(void, item, "setTarget:", macos.Ref, target);
            macos.send1(void, item, "setTag:", isize, @intCast(50 + i));
            macos.send1(void, item, "setState:", isize, if (self.source == @as(state.MediaSource, @enumFromInt(i))) 1 else 0);
            macos.send1(void, source_submenu, "addItem:", macos.Ref, item);
        }
        macos.send1(void, source_item, "setSubmenu:", macos.Ref, source_submenu);
        macos.send1(void, menu, "addItem:", macos.Ref, source_item);

        const mode_title = macos.string("Widget Mode");
        defer macos.CFRelease(mode_title);
        const mode_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, mode_title, macos.Ref, null, macos.Ref, empty_str);
        const mode_submenu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, mode_title);
        macos.send1(void, mode_submenu, "setAutoenablesItems:", bool, false);
        const modes = [_][]const u8{ "Compact", "Expanded" };
        for (modes, 0..) |mode_name, i| {
            const mode_str = macos.string(mode_name);
            defer macos.CFRelease(mode_str);
            const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, mode_str, macos.Ref, choose_sel, macos.Ref, empty_str);
            macos.send1(void, item, "setTarget:", macos.Ref, target);
            macos.send1(void, item, "setTag:", isize, @intCast(60 + i));
            macos.send1(void, item, "setState:", isize, if (self.mode == @as(state.WidgetMode, @enumFromInt(i))) 1 else 0);
            macos.send1(void, mode_submenu, "addItem:", macos.Ref, item);
        }
        macos.send1(void, mode_item, "setSubmenu:", macos.Ref, mode_submenu);
        macos.send1(void, menu, "addItem:", macos.Ref, mode_item);

        const idle_title = macos.string("Idle Style");
        defer macos.CFRelease(idle_title);
        const idle_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, idle_title, macos.Ref, null, macos.Ref, empty_str);
        const idle_submenu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, idle_title);
        macos.send1(void, idle_submenu, "setAutoenablesItems:", bool, false);
        const idles = [_][]const u8{ "Open Spotify", "Cat", "Banana Cat" };
        for (idles, 0..) |idle_name, i| {
            const idle_str = macos.string(idle_name);
            defer macos.CFRelease(idle_str);
            const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, idle_str, macos.Ref, choose_sel, macos.Ref, empty_str);
            macos.send1(void, item, "setTarget:", macos.Ref, target);
            macos.send1(void, item, "setTag:", isize, @intCast(80 + i));
            macos.send1(void, item, "setState:", isize, if (state.setting_idle_style == @as(state.IdleStyle, @enumFromInt(i))) 1 else 0);
            macos.send1(void, idle_submenu, "addItem:", macos.Ref, item);
        }
        macos.send1(void, idle_item, "setSubmenu:", macos.Ref, idle_submenu);
        macos.send1(void, menu, "addItem:", macos.Ref, idle_item);

        macos.send1(void, menu, "addItem:", macos.Ref, macos.send0(macos.Ref, item_cls, "separatorItem"));

        const set_title = macos.string("Widget Settings");
        defer macos.CFRelease(set_title);
        const settings_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, set_title, macos.Ref, null, macos.Ref, empty_str);
        const submenu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, set_title);
        macos.send1(void, submenu, "setAutoenablesItems:", bool, false);

        const prefs = [_][]const u8{ "Artwork Glow", "Animations", "Dim Artwork When Paused" };
        const enabled = [_]c_int{ self.glow, self.animations, self.dim };

        for (prefs, 0..) |p_name, i| {
            const s = macos.string(p_name);
            defer macos.CFRelease(s);
            const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, s, macos.Ref, choose_sel, macos.Ref, empty_str);
            macos.send1(void, item, "setTarget:", macos.Ref, target);
            macos.send1(void, item, "setTag:", isize, @intCast(i + 5));
            macos.send1(void, item, "setState:", isize, if (enabled[i] != 0) 1 else 0);
            macos.send1(void, submenu, "addItem:", macos.Ref, item);
        }

        macos.send1(void, submenu, "addItem:", macos.Ref, macos.send0(macos.Ref, item_cls, "separatorItem"));

        const groups = [_][]const u8{ "Frame Strength", "Glow Intensity", "Animation Speed" };
        const choices = [_][3][]const u8{
            .{ "Off", "Subtle", "Strong" },
            .{ "Low", "Normal", "High" },
            .{ "Slow", "Normal", "Fast" },
        };
        const selected = [_]u8{ @intFromEnum(self.frame), @intFromEnum(self.intensity), @intFromEnum(self.speed) };

        for (groups, 0..) |grp, g| {
            const grp_str = macos.string(grp);
            defer macos.CFRelease(grp_str);
            const parent_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, grp_str, macos.Ref, null, macos.Ref, empty_str);
            const options_menu = macos.send1(macos.Ref, macos.send0(macos.Ref, menu_cls, "alloc"), "initWithTitle:", macos.Ref, grp_str);
            macos.send1(void, options_menu, "setAutoenablesItems:", bool, false);

            for (choices[g], 0..) |opt_name, o| {
                const opt_str = macos.string(opt_name);
                defer macos.CFRelease(opt_str);
                const item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, opt_str, macos.Ref, choose_sel, macos.Ref, empty_str);
                macos.send1(void, item, "setTarget:", macos.Ref, target);
                macos.send1(void, item, "setTag:", isize, @intCast((g + 1) * 10 + o));
                macos.send1(void, item, "setState:", isize, if (selected[g] == o) 1 else 0);
                macos.send1(void, options_menu, "addItem:", macos.Ref, item);
            }

            macos.send1(void, parent_item, "setSubmenu:", macos.Ref, options_menu);
            macos.send1(void, submenu, "addItem:", macos.Ref, parent_item);
        }

        macos.send1(void, submenu, "addItem:", macos.Ref, macos.send0(macos.Ref, item_cls, "separatorItem"));

        const reset_str = macos.string("Restore Defaults");
        defer macos.CFRelease(reset_str);
        const reset_item = macos.send3(macos.Ref, macos.send0(macos.Ref, item_cls, "alloc"), "initWithTitle:action:keyEquivalent:", macos.Ref, reset_str, macos.Ref, choose_sel, macos.Ref, empty_str);
        macos.send1(void, reset_item, "setTarget:", macos.Ref, target);
        macos.send1(void, reset_item, "setTag:", isize, 40);
        macos.send1(void, submenu, "addItem:", macos.Ref, reset_item);

        macos.send1(void, settings_item, "setSubmenu:", macos.Ref, submenu);
        macos.send1(void, menu, "addItem:", macos.Ref, settings_item);

        _ = macos.send3(bool, menu, "popUpMenuPositioningItem:atLocation:inView:", macos.Ref, null, macos.Point, location, macos.Ref, null);

        if (previous_app != null) {
            const proc_info = macos.send0(macos.Ref, macos.objc_getClass("NSProcessInfo"), "processInfo");
            const my_pid = macos.send0(i32, proc_info, "processIdentifier");
            const prev_pid = macos.send0(i32, previous_app, "processIdentifier");
            if (prev_pid != my_pid) {
                _ = macos.send1(bool, previous_app, "activateWithOptions:", usize, 0);
            }
        }
        menu_open.store(false, .monotonic);
    }
};

pub export fn widget_context_menu(playing: c_int, glow: c_int, animations: c_int, dim: c_int, frame: state.FrameStrength, intensity: state.GlowIntensity, speed: state.AnimationSpeed, source: state.MediaSource, mode: state.WidgetMode) callconv(.c) void {
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
    macos.dispatch_async_f(macos.dispatch_get_main_queue(), ctx, ContextMenuCtx.show);
}
