const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const swift_target = b.fmt("{s}-apple-macosx12.0", .{switch (target.result.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        else => @panic("Wallify requires an Apple desktop architecture"),
    }});
    const debug_inspector = b.option(bool, "debug-inspector", "Build the Dear ImGui developer inspector") orelse false;
    const macos_sdk = std.mem.trim(u8, b.run(&.{ "xcrun", "--sdk", "macosx", "--show-sdk-path" }), " \n\r\t");

    const build_options = b.addOptions();
    build_options.addOption(bool, "debug_inspector", debug_inspector);

    // Decode source PNGs once per asset change; outputs live only in Zig's cache.

    // MediaRemote bridge loaded by the Perl metadata helper.
    const metadata = b.addSystemCommand(&.{
        "xcrun",                            "swiftc",                     "-swift-version",     "5",                          "-emit-library",
        "-module-name",                     "MetadataFetcher",            "-module-cache-path", "/tmp/wallify-swift-modules", "-target",
        swift_target,                       "-no-toolchain-stdlib-rpath", "-Xlinker",           "-install_name",              "-Xlinker",
        "@rpath/libmetadata_fetcher.dylib",
    });
    metadata.addArg(if (optimize == .Debug) "-Onone" else "-O");
    metadata.addFileArg(b.path("src/media/metadata_fetcher.swift"));
    metadata.addArg("-o");
    const metadata_dylib = metadata.addOutputFileArg("libmetadata_fetcher.dylib");
    b.getInstallStep().dependOn(&b.addInstallFile(metadata_dylib, "lib/libmetadata_fetcher.dylib").step);

    // SwiftUI settings retains the existing C settings contract.
    const swift_settings = b.addSystemCommand(&.{
        "xcrun",        "swiftc",          "-swift-version",     "5",                               "-emit-library",
        "-module-name", "WallifySettings", "-module-cache-path", "/tmp/wallify-swift-modules",      "-target",
        swift_target,   "-Xlinker",        "-undefined",         "-Xlinker",                        "dynamic_lookup",
        "-Xlinker",     "-install_name",   "-Xlinker",           "@rpath/libWallifySettings.dylib", "-no-toolchain-stdlib-rpath",
    });
    swift_settings.addArg(if (optimize == .Debug) "-Onone" else "-O");
    swift_settings.addArg("-import-objc-header");
    swift_settings.addFileArg(b.path("src/platform/settings_bridge.h"));
    swift_settings.addFileInput(b.path("src/platform/settings_window.h"));
    swift_settings.addFileInput(b.path("src/platform/debug_stats.h"));
    swift_settings.addFileInput(b.path("src/platform/gpu.h"));
    swift_settings.addFileInput(b.path("src/platform/media_core.h"));
    swift_settings.addFileInput(b.path("src/platform/layout.h"));
    swift_settings.addFileInput(b.path("src/platform/widget_state.h"));
    swift_settings.addFileArg(b.path("src/widget_state.swift"));
    swift_settings.addFileArg(b.path("src/settings.swift"));
    swift_settings.addFileArg(b.path("src/platform/settings_window.swift"));
    swift_settings.addFileArg(b.path("src/platform/application.swift"));
    swift_settings.addFileArg(b.path("src/platform/widget_window.swift"));
    swift_settings.addFileArg(b.path("src/ui/context_menu.swift"));
    swift_settings.addFileArg(b.path("src/ui/layout.swift"));
    swift_settings.addFileArg(b.path("src/ui/input.swift"));
    swift_settings.addFileArg(b.path("src/platform/metal_renderer.swift"));
    swift_settings.addFileArg(b.path("src/platform/desktop_glass.swift"));
    swift_settings.addFileArg(b.path("src/platform/desktop_snap.swift"));
    swift_settings.addFileArg(b.path("src/platform/idle_animation.swift"));
    swift_settings.addFileArg(b.path("src/platform/frame_wakeup.swift"));
    swift_settings.addFileArg(b.path("src/platform/media_keys.swift"));
    swift_settings.addFileArg(b.path("src/platform/media_remote.swift"));
    swift_settings.addFileArg(b.path("src/media/spotify.swift"));
    swift_settings.addFileArg(b.path("src/media/spotifast.swift"));
    swift_settings.addFileArg(b.path("src/media/artwork_download.swift"));
    swift_settings.addFileArg(b.path("src/media/action_queue.swift"));
    swift_settings.addFileArg(b.path("src/media/playback.swift"));
    swift_settings.addFileArg(b.path("src/media/payload.swift"));
    swift_settings.addFileArg(b.path("src/media/controller.swift"));
    swift_settings.addFileArg(b.path("src/media/helper.swift"));
    swift_settings.addFileArg(b.path("src/graphics/raster.swift"));
    swift_settings.addFileArg(b.path("src/graphics/sprites.swift"));
    swift_settings.addFileArg(b.path("src/graphics/motion.swift"));
    swift_settings.addFileArg(b.path("src/graphics/commands.swift"));
    swift_settings.addFileArg(b.path("src/graphics/canvas.swift"));
    swift_settings.addFileArg(b.path("src/graphics/assets.swift"));
    swift_settings.addFileArg(b.path("src/graphics/text_cache.swift"));
    swift_settings.addFileArg(b.path("src/graphics/player.swift"));
    swift_settings.addFileArg(b.path("src/graphics/render.swift"));
    swift_settings.addFileArg(b.path("src/graphics/animation.swift"));
    swift_settings.addFileArg(b.path("src/graphics/idle_compositor.swift"));
    swift_settings.addArg("-o");
    const settings_dylib = swift_settings.addOutputFileArg("libWallifySettings.dylib");
    b.getInstallStep().dependOn(&b.addInstallFile(settings_dylib, "lib/libWallifySettings.dylib").step);

    // Desktop player.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkMacos(mod);
    mod.addObjectFile(settings_dylib);
    mod.addRPathSpecial("@executable_path/../lib");
    mod.addRPathSpecial("@executable_path/../Frameworks");
    mod.linkFramework("ServiceManagement", .{});
    mod.addOptions("build_options", build_options);
    mod.addIncludePath(b.path("src/platform"));
    mod.linkFramework("Metal", .{});
    mod.linkFramework("MetalPerformanceShaders", .{});
    mod.linkFramework("QuartzCore", .{});

    if (debug_inspector) {
        const imgui_dir = ".zig-cache/wallify-imgui";
        mod.addIncludePath(b.path(imgui_dir));
        mod.addObjectFile(.{ .cwd_relative = b.fmt("{s}/usr/lib/libc++.tbd", .{macos_sdk}) });
        mod.addIncludePath(b.path(b.fmt("{s}/backends", .{imgui_dir})));
        mod.linkFramework("MetalKit", .{});
        mod.linkFramework("GameController", .{});

        const imgui_sources = [_][]const u8{
            "imgui.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
            "backends/imgui_impl_osx.mm",
            "backends/imgui_impl_metal.mm",
        };

        for (imgui_sources, 0..) |source, index| {
            const compile = b.addSystemCommand(&.{
                "/usr/bin/clang++",
                "-std=c++17",
                "-fobjc-arc",
                "-fmodules",
                "-Wno-deprecated-declarations",
                "-I.zig-cache/wallify-imgui",
                "-I.zig-cache/wallify-imgui/backends",
                "-c",
            });
            compile.addFileArg(b.path(b.fmt(".zig-cache/wallify-imgui/{s}", .{source})));
            compile.addArg("-o");
            mod.addObjectFile(compile.addOutputFileArg(
                b.fmt("wallify-imgui-{d}.o", .{index}),
            ));
        }

        const bridge = b.addSystemCommand(&.{
            "/usr/bin/clang++",
            "-std=c++17",
            "-fobjc-arc",
            "-fmodules",
            "-Wno-deprecated-declarations",
            "-I.zig-cache/wallify-imgui",
            "-I.zig-cache/wallify-imgui/backends",
            "-c",
        });
        bridge.addFileArg(b.path("src/ui/debug_imgui.mm"));
        bridge.addFileInput(b.path("src/platform/debug_stats.h"));
        bridge.addFileInput(b.path("src/platform/gpu.h"));
        bridge.addArg("-o");
        mod.addObjectFile(bridge.addOutputFileArg("wallify-debug-imgui.o"));
    }

    const metal_c = b.addSystemCommand(&.{ "xcrun", "-sdk", "macosx", "metal", "-fmodules-cache-path=/tmp/wallify-metal-modules", "-c" });
    metal_c.addArg("-include");
    metal_c.addFileArg(b.path("src/platform/gpu.h"));
    metal_c.addFileArg(b.path("src/platform/shaders.metal"));
    metal_c.addArg("-o");
    const metal_air = metal_c.addOutputFileArg("shaders.air");

    const metallib_cmd = b.addSystemCommand(&.{ "xcrun", "-sdk", "macosx", "metallib" });
    metallib_cmd.addFileArg(metal_air);
    metallib_cmd.addArg("-o");
    const metallib_out = metallib_cmd.addOutputFileArg("default.metallib");

    const exe = b.addExecutable(.{
        .name = "wallify",
        .root_module = mod,
    });
    retainSettingsBridge(exe);
    b.installArtifact(exe);
    const install_metal = b.addInstallBinFile(metallib_out, "default.metallib");
    b.getInstallStep().dependOn(&install_metal.step);

    const copy_app_bin = b.addInstallFile(exe.getEmittedBin(), "Wallify.app/Contents/MacOS/Wallify");
    b.getInstallStep().dependOn(&copy_app_bin.step);
    const copy_app_metal = b.addInstallFile(metallib_out, "Wallify.app/Contents/Resources/default.metallib");
    b.getInstallStep().dependOn(&copy_app_metal.step);

    const run_step = b.step("run", "Run the player");
    run_step.dependOn(b.getInstallStep());
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const test_step = b.step("test", "Run unit tests");
    const helper_check = b.addSystemCommand(&.{
        "/usr/bin/perl", "-e",
        "use DynaLoader; use Cwd qw(abs_path); open(STDOUT, '>', '/dev/null') or die $!; " ++
            "my $h = DynaLoader::dl_load_file(abs_path($ARGV[0])) or die DynaLoader::dl_error(); " ++
            "for my $name (qw(mrc_printNowPlayingInfo mrc_notifications_init mrc_wait_for_notification mrc_sendCommand)) { " ++
            "my $s = DynaLoader::dl_find_symbol($h, $name) or die qq(missing $name); " ++
            "DynaLoader::dl_install_xsub(qq(main::$name), $s); } " ++
            "mrc_notifications_init(); mrc_notifications_init(); mrc_printNowPlayingInfo();",
    });
    helper_check.addFileArg(metadata_dylib);
    test_step.dependOn(&helper_check.step);
    const test_artifact = b.addTest(.{
        .root_module = mod,
    });
    retainSettingsBridge(test_artifact);
    test_artifact.root_module.addRPath(settings_dylib.dirname());
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);

    const swift_check = b.addSystemCommand(&.{
        "xcrun",              "swiftc",                     "-swift-version", "5",
        "-module-cache-path", "/tmp/wallify-swift-modules",
    });
    swift_check.addArg("-import-objc-header");
    swift_check.addFileArg(b.path("src/platform/settings_bridge.h"));
    swift_check.addFileInput(b.path("src/platform/settings_window.h"));
    swift_check.addFileInput(b.path("src/platform/debug_stats.h"));
    swift_check.addFileInput(b.path("src/platform/gpu.h"));
    swift_check.addFileInput(b.path("src/platform/media_core.h"));
    swift_check.addFileInput(b.path("src/platform/layout.h"));
    swift_check.addFileInput(b.path("src/platform/widget_state.h"));
    swift_check.addFileArg(b.path("src/widget_state.swift"));
    swift_check.addFileArg(b.path("src/settings.swift"));
    swift_check.addFileArg(b.path("src/platform/settings_window.swift"));
    swift_check.addFileArg(b.path("src/platform/application.swift"));
    swift_check.addFileArg(b.path("src/platform/widget_window.swift"));
    swift_check.addFileArg(b.path("src/ui/context_menu.swift"));
    swift_check.addFileArg(b.path("src/ui/layout.swift"));
    swift_check.addFileArg(b.path("src/ui/input.swift"));
    swift_check.addFileArg(b.path("src/platform/metal_renderer.swift"));
    swift_check.addFileArg(b.path("src/platform/desktop_glass.swift"));
    swift_check.addFileArg(b.path("src/platform/desktop_snap.swift"));
    swift_check.addFileArg(b.path("src/platform/idle_animation.swift"));
    swift_check.addFileArg(b.path("src/platform/frame_wakeup.swift"));
    swift_check.addFileArg(b.path("src/platform/media_keys.swift"));
    swift_check.addFileArg(b.path("src/platform/media_remote.swift"));
    swift_check.addFileArg(b.path("src/media/spotify.swift"));
    swift_check.addFileArg(b.path("src/media/spotifast.swift"));
    swift_check.addFileArg(b.path("src/media/artwork_download.swift"));
    swift_check.addFileArg(b.path("src/media/action_queue.swift"));
    swift_check.addFileArg(b.path("src/media/playback.swift"));
    swift_check.addFileArg(b.path("src/media/payload.swift"));
    swift_check.addFileArg(b.path("src/media/controller.swift"));
    swift_check.addFileArg(b.path("src/media/helper.swift"));
    swift_check.addFileArg(b.path("src/media/metadata_fetcher.swift"));
    swift_check.addFileArg(b.path("src/graphics/raster.swift"));
    swift_check.addFileArg(b.path("src/graphics/sprites.swift"));
    swift_check.addFileArg(b.path("src/graphics/motion.swift"));
    swift_check.addFileArg(b.path("src/graphics/commands.swift"));
    swift_check.addFileArg(b.path("src/graphics/canvas.swift"));
    swift_check.addFileArg(b.path("src/graphics/assets.swift"));
    swift_check.addFileArg(b.path("src/graphics/text_cache.swift"));
    swift_check.addFileArg(b.path("src/graphics/player.swift"));
    swift_check.addFileArg(b.path("src/graphics/render.swift"));
    swift_check.addFileArg(b.path("src/graphics/animation.swift"));
    swift_check.addFileArg(b.path("src/graphics/idle_compositor.swift"));
    swift_check.addFileArg(b.path("tests/configuration.swift"));
    swift_check.addFileArg(b.path("tests/media_coordination.swift"));
    swift_check.addFileArg(b.path("tests/pointer_actions.swift"));
    swift_check.addFileArg(b.path("tests/scene_assets.swift"));
    swift_check.addFileArg(b.path("tests/animation_coordination.swift"));
    swift_check.addFileArg(b.path("tests/settings_bridge.swift"));
    swift_check.addArg("-o");
    const check_binary = swift_check.addOutputFileArg("settings-bridge-check");
    const run_check = b.addSystemCommand(&.{"/usr/bin/env"});
    run_check.addFileArg(check_binary);
    run_check.addArg("--metallib");
    run_check.addFileArg(metallib_out);
    test_step.dependOn(&run_check.step);
    const run_flag_check = b.addSystemCommand(&.{"/usr/bin/env"});
    run_flag_check.addFileArg(check_binary);
    run_flag_check.addArg("--settings");
    run_flag_check.addArg("--metallib");
    run_flag_check.addFileArg(metallib_out);
    test_step.dependOn(&run_flag_check.step);
}

fn linkMacos(module: *std.Build.Module) void {
    module.linkSystemLibrary("objc", .{});
    module.linkFramework("Foundation", .{});
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("CoreText", .{});
    module.linkFramework("AppKit", .{});
    module.linkFramework("CoreGraphics", .{});
}

// Swift resolves these callbacks from its host executable. Keep them through
// dead stripping, and reject a missing callback at link time rather than launch.
fn retainSettingsBridge(artifact: *std.Build.Step.Compile) void {
    artifact.rdynamic = true;
    for ([_][]const u8{
        "_wallify_settings_get_snapshot",   "_wallify_settings_apply_bool",
        "_wallify_settings_apply_int",      "_wallify_settings_restore_defaults",
        "_wallify_settings_reset_position", "_wallify_settings_path",
        "_wallify_open_inspector",          "_wallify_menu_play_pause",
        "_wallify_menu_previous",           "_wallify_menu_next",
        "_wallify_pointer",                 "_wallify_set_window_visible",
        "_wallify_media_key_event",         "_widget_debug_window_show",
        "_widget_debug_window_hide",        "_wallify_context_menu_selected",
        "_wallify_artwork_downloaded",      "_wallify_execute_media_command",
        "_wallify_execute_media_seek",      "_wallify_clear_artwork",
        "_wallify_extract_color",           "_widget_start_drag",
        "_widget_nearby_panel_snap",        "_widget_show_snap_outline",
        "_widget_hide_snap_outline",        "_widget_set_snap_debug",
    }) |symbol| artifact.forceUndefinedSymbol(symbol);
}
