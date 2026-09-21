
        const settings_win_str = macos.string("Settings…");
        defer macos.CFRelease(settings_win_str);
        const comma_str = macos.string(",");
        defer macos.CFRelease(comma_str);
        const settings_win_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ settings_win_str, choose_sel, comma_str }));
        macos.send(void, settings_win_item, "setTarget:", .{target});
        macos.send(void, settings_win_item, "setTag:", .{@as(isize, 90)});
        macos.send(void, menu, "addItem:", .{settings_win_item});

        macos.send(void, menu, "addItem:", .{macos.send(macos.Ref, item_cls, "separatorItem", .{})});

        const ns_app = macos.send(macos.Ref, macos.objc_getClass("NSApplication"), "sharedApplication", .{});

        const quit_str = macos.string("Quit Wallify");
        defer macos.CFRelease(quit_str);
        const quit_item = autorelease(macos.send(macos.Ref, macos.send(macos.Ref, item_cls, "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ quit_str, macos.sel_registerName("terminate:"), empty_str }));
        macos.send(void, quit_item, "setTarget:", .{ns_app});
        macos.send(void, menu, "addItem:", .{quit_item});

        const context_view = native.wallify_context_menu_view();
        if (context_event != null and context_view != null) {
            // Use the completed right-click event and its originating view so
            // AppKit owns mouse tracking/highlighting immediately.
            _ = macos.send(void, menu_cls, "popUpContextMenu:withEvent:forView:", .{
                menu,