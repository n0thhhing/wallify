const std = @import("std");
const state = @import("../state.zig");
const macos = @import("../platform/macos.zig");
const native = @import("../platform/native.zig");

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

var menu_action: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(0);
var menu_open: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn chooseCallback(_: macos.Ref, _: macos.Ref, sender: macos.Ref) callconv(.c) void {
    const tag = macos.send(isize, sender, "tag", .{});
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
                    instance = macos.send(macos.Ref, macos.send(macos.Ref, cls, "alloc", .{}), "init", .{});
                }
            }
            return instance;
        }
    };
    return TargetHolder.get();
}

fn autorelease(obj: macos.Ref) macos.Ref {
    if (obj != null) {
        return macos.send(macos.Ref, obj, "autorelease", .{});
    }
    return obj;
}

fn shouldPresentContextMenuSynchronously(is_main_thread: bool) bool {
    return is_main_thread;
}

fn presentContextMenuSynchronously() bool {
    return shouldPresentContextMenuSynchronously(
        macos.send(bool, macos.objc_getClass("NSThread"), "isMainThread", .{}),
    );
}

pub export fn widget_context_menu_action() callconv(.c) ContextMenuAction {
    return @enumFromInt(menu_action.swap(0, .monotonic));
}

test "context menu presentation stays synchronous on the AppKit main thread" {
    try std.testing.expect(shouldPresentContextMenuSynchronously(true));
    try std.testing.expect(!shouldPresentContextMenuSynchronously(false));
}

pub const ContextMenuCtx = struct {
    playing: c_int,
    glow: c_int,
    aurora: c_int,
    animations: c_int,
    dim: c_int,
    frame: state.FrameStrength,
    intensity: state.GlowIntensity,
    speed: state.AnimationSpeed,
    source: state.MediaSource,
    mode: state.WidgetMode,
    transition: state.TransitionStyle,

    fn show(ctx_ptr: macos.Ref) callconv(.c) void {
        const self: *ContextMenuCtx = @ptrCast(@alignCast(ctx_ptr));
        defer std.heap.c_allocator.destroy(self);

        const ns_app = macos.send(macos.Ref, macos.objc_getClass("NSApplication"), "sharedApplication", .{});
        const ns_ws = macos.send(macos.Ref, macos.objc_getClass("NSWorkspace"), "sharedWorkspace", .{});
        const previous_app = macos.send(macos.Ref, ns_ws, "frontmostApplication", .{});
        const context_event = native.wallify_context_menu_event();

        _ = macos.send(bool, ns_app, "activateIgnoringOtherApps:", .{true});

        const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
        defer macos.send(void, pool, "release", .{});

        const target = getMenuTarget();
        const menu_cls = macos.objc_getClass("NSMenu");
        const item_cls = macos.objc_getClass("NSMenuItem");

        const title_str = macos.string("Wallify");
        defer macos.CFRelease(title_str);
        const menu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{title_str}));
        macos.send(void, menu, "setAutoenablesItems:", .{false});

        const empty_str = macos.string("");
        defer macos.CFRelease(empty_str);

        const main_labels = [_][]const u8{
            if (self.playing != 0) "Pause" else "Play",
            "Previous Track",
            "Next Track",
            if (self.source == .spotifast) "Open Spotifast" else "Open Spotify",
        };

        const choose_sel = macos.sel_registerName("choose:");

        for (main_labels, 0..) |lbl, i| {
            const s = macos.string(lbl);
            defer macos.CFRelease(s);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ s, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, @intCast(i + 1))});
            macos.send(void, menu, "addItem:", .{item});
        }

        macos.send(void, menu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const source_title = macos.string("Media Source");
        defer macos.CFRelease(source_title);
        const source_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ source_title, @as(macos.Ref, null), empty_str }));
        const source_submenu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{source_title}));
        macos.send(void, source_submenu, "setAutoenablesItems:", .{false});

        const sources = [_][]const u8{ "Now Playing", "Spotify", "Spotifast" };
        for (sources, 0..) |src_name, i| {
            const s = macos.string(src_name);
            defer macos.CFRelease(s);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ s, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, @intCast(50 + i))});
            macos.send(void, item, "setState:", .{@as(isize, if (self.source == @as(state.MediaSource, @enumFromInt(i))) 1 else 0)});
            macos.send(void, source_submenu, "addItem:", .{item});
        }
        macos.send(void, source_item, "setSubmenu:", .{source_submenu});
        macos.send(void, menu, "addItem:", .{source_item});

        const mode_title = macos.string("Widget Mode");
        defer macos.CFRelease(mode_title);
        const mode_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ mode_title, @as(macos.Ref, null), empty_str }));
        const mode_submenu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{mode_title}));
        macos.send(void, mode_submenu, "setAutoenablesItems:", .{false});
        const modes = [_][]const u8{ "1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2" };
        for (modes, 0..) |mode_name, i| {
            const mode_str = macos.string(mode_name);
            defer macos.CFRelease(mode_str);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ mode_str, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, @intCast(60 + i))});
            macos.send(void, item, "setState:", .{@as(isize, if (self.mode == @as(state.WidgetMode, @enumFromInt(i))) 1 else 0)});
            macos.send(void, mode_submenu, "addItem:", .{item});
        }
        macos.send(void, mode_item, "setSubmenu:", .{mode_submenu});
        macos.send(void, menu, "addItem:", .{mode_item});

        const idle_title = macos.string("Idle Style");
        defer macos.CFRelease(idle_title);
        const idle_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ idle_title, @as(macos.Ref, null), empty_str }));
        const idle_submenu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{idle_title}));
        macos.send(void, idle_submenu, "setAutoenablesItems:", .{false});
        const idles = [_]struct { name: []const u8, tag: c_int, style: state.IdleStyle }{
            .{ .name = "Pixel Cat", .tag = 81, .style = .pixel_cat },
            .{ .name = "Banana Cat", .tag = 82, .style = .banana_cat },
            .{ .name = "Raccoon", .tag = 83, .style = .raccoon },
            .{ .name = "Spotify Launcher", .tag = 80, .style = .spotify },
        };
        for (idles) |idle_opt| {
            const idle_str = macos.string(idle_opt.name);
            defer macos.CFRelease(idle_str);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ idle_str, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, idle_opt.tag)});
            macos.send(void, item, "setState:", .{@as(isize, if (state.setting_idle_style == idle_opt.style) 1 else 0)});
            macos.send(void, idle_submenu, "addItem:", .{item});
        }
        macos.send(void, idle_item, "setSubmenu:", .{idle_submenu});
        macos.send(void, menu, "addItem:", .{idle_item});

        const trans_title = macos.string("Track Transition");
        defer macos.CFRelease(trans_title);
        const trans_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ trans_title, @as(macos.Ref, null), empty_str }));
        const trans_submenu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{trans_title}));
        macos.send(void, trans_submenu, "setAutoenablesItems:", .{false});
        const trans_choices = [_][]const u8{ "Default", "Cinematic", "Liquid Ripple", "3D Card Flip", "Vinyl Spin", "Cyber Glitch" };
        for (trans_choices, 0..) |choice_name, i| {
            const choice_str = macos.string(choice_name);
            defer macos.CFRelease(choice_str);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ choice_str, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, @intCast(70 + i))});
            macos.send(void, item, "setState:", .{@as(isize, if (self.transition == @as(state.TransitionStyle, @enumFromInt(i))) 1 else 0)});
            macos.send(void, trans_submenu, "addItem:", .{item});
        }
        macos.send(void, trans_item, "setSubmenu:", .{trans_submenu});
        macos.send(void, menu, "addItem:", .{trans_item});

        macos.send(void, menu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const set_title = macos.string("Quick Preferences");
        defer macos.CFRelease(set_title);
        const settings_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ set_title, @as(macos.Ref, null), empty_str }));
        const submenu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{set_title}));
        macos.send(void, submenu, "setAutoenablesItems:", .{false});

        const prefs = [_][]const u8{ "Artwork Glow", "Dynamic Aurora", "Animations", "Dim Artwork When Paused" };
        const enabled = [_]c_int{ self.glow, self.aurora, self.animations, self.dim };

        for (prefs, 0..) |p_name, i| {
            const s = macos.string(p_name);
            defer macos.CFRelease(s);
            const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ s, choose_sel, empty_str }));
            macos.send(void, item, "setTarget:", .{target});
            macos.send(void, item, "setTag:", .{@as(isize, @intCast(i + 5))});
            macos.send(void, item, "setState:", .{@as(isize, if (enabled[i] != 0) 1 else 0)});
            macos.send(void, submenu, "addItem:", .{item});
        }

        macos.send(void, submenu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

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
            const parent_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ grp_str, @as(macos.Ref, null), empty_str }));
            const options_menu = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, menu_cls, "alloc", .{}), "initWithTitle:", .{grp_str}));
            macos.send(void, options_menu, "setAutoenablesItems:", .{false});

            for (choices[g], 0..) |opt_name, o| {
                const opt_str = macos.string(opt_name);
                defer macos.CFRelease(opt_str);
                const item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ opt_str, choose_sel, empty_str }));
                macos.send(void, item, "setTarget:", .{target});
                macos.send(void, item, "setTag:", .{@as(isize, @intCast((g + 1) * 10 + o))});
                macos.send(void, item, "setState:", .{@as(isize, if (selected[g] == o) 1 else 0)});
                macos.send(void, options_menu, "addItem:", .{item});
            }

            macos.send(void, parent_item, "setSubmenu:", .{options_menu});
            macos.send(void, submenu, "addItem:", .{parent_item});
        }

        macos.send(void, submenu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const defaults_str = macos.string("Restore Defaults");
        defer macos.CFRelease(defaults_str);
        const defaults_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ defaults_str, choose_sel, empty_str }));
        macos.send(void, defaults_item, "setTarget:", .{target});
        macos.send(void, defaults_item, "setTag:", .{@as(isize, 40)});
        macos.send(void, submenu, "addItem:", .{defaults_item});

        macos.send(void, settings_item, "setSubmenu:", .{submenu});
        macos.send(void, menu, "addItem:", .{settings_item});

        macos.send(void, menu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const settings_win_str = macos.string("Settings…");
        defer macos.CFRelease(settings_win_str);
        const comma_str = macos.string(",");
        defer macos.CFRelease(comma_str);
        const settings_win_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ settings_win_str, choose_sel, comma_str }));
        macos.send(void, settings_win_item, "setTarget:", .{target});
        macos.send(void, settings_win_item, "setTag:", .{@as(isize, 90)});
        macos.send(void, menu, "addItem:", .{settings_win_item});

        macos.send(void, menu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const quit_str = macos.string("Quit Wallify");
        defer macos.CFRelease(quit_str);
        const quit_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ quit_str, macos.sel_registerName("terminate:"), empty_str }));
        macos.send(void, quit_item, "setTarget:", .{ns_app});
        macos.send(void, menu, "addItem:", .{quit_item});

        if (context_event) |event| {
            // This is an NSMenu class method. Pass the actual right-click event
            // so AppKit starts tracking/highlighting immediately.
            _ = macos.send(void, menu_cls, "popUpContextMenu:withEvent:forView:", .{ menu, event, @as(macos.Ref, null) });
        } else {
            const location = macos.send(macos.Point, macos.objc_getClass("NSEvent"), "mouseLocation", .{});
            _ = macos.send(bool, menu, "popUpMenuPositioningItem:atLocation:inView:", .{ @as(macos.Ref, null), location, @as(macos.Ref, null) });
        }
        native.wallify_clear_context_menu_event();

        if (previous_app != null) {
            _ = macos.send(bool, previous_app, "activateWithOptions:", .{@as(usize, 0)});
        }
        menu_open.store(false, .monotonic);
    }
};

pub export fn widget_context_menu(playing: c_int, glow: c_int, aurora: c_int, animations: c_int, dim: c_int, frame: state.FrameStrength, intensity: state.GlowIntensity, speed: state.AnimationSpeed, source: state.MediaSource, mode: state.WidgetMode, transition: state.TransitionStyle) callconv(.c) void {
    if (menu_open.swap(true, .monotonic)) return;
    const ctx = std.heap.c_allocator.create(ContextMenuCtx) catch {
        menu_open.store(false, .monotonic);
        return;
    };
    ctx.* = .{
        .playing = playing,
        .glow = glow,
        .aurora = aurora,
        .animations = animations,
        .dim = dim,
        .frame = frame,
        .intensity = intensity,
        .speed = speed,
        .source = source,
        .mode = mode,
        .transition = transition,
    };
    if (presentContextMenuSynchronously()) {
        // Right-click arrives on the AppKit main thread. Present the menu in
        // this event handler so AppKit gets the original NSEvent and starts
        // mouse tracking/highlighting immediately.
        ContextMenuCtx.show(@ptrCast(ctx));
    } else {
        macos.dispatch_async_f(macos.dispatch_get_main_queue(), ctx, ContextMenuCtx.show);
    }
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
