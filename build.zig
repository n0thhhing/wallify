const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const debug_inspector = b.option(bool, "debug-inspector", "Build the Dear ImGui developer inspector") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "debug_inspector", debug_inspector);

    // Decode source PNGs once per asset change; outputs live only in Zig's cache.

    // MediaRemote bridge loaded by the Perl metadata helper.
    const dylib = b.addLibrary(.{
        .name = "metadata_fetcher",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/media/metadata_fetcher.zig"),
            .link_libc = true,
        }),
    });
    dylib.root_module.linkFramework("CoreFoundation", .{});
    b.installArtifact(dylib);

    // Desktop player.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkMacos(mod);
    mod.addOptions("build_options", build_options);
    mod.addIncludePath(b.path("src/platform"));
    const native = b.addSystemCommand(&.{ "/usr/bin/clang", "-c", "-fobjc-arc", "-fmodules", "-fmodules-cache-path=/tmp/wallify-clang-modules" });
    native.addArg("-include");
    native.addFileArg(b.path("src/platform/gpu.h"));
    native.addFileArg(b.path("src/platform/native.m"));
    native.addFileInput(b.path("src/platform/settings_window.m"));
    native.addFileInput(b.path("src/platform/settings_window.h"));
    native.addArg("-o");
    mod.addObjectFile(native.addOutputFileArg("native.o"));
    mod.linkFramework("Metal", .{});
    mod.linkFramework("MetalPerformanceShaders", .{});
    mod.linkFramework("QuartzCore", .{});

    if (debug_inspector) {
        const imgui_dir = ".zig-cache/wallify-imgui";
        mod.addIncludePath(b.path(imgui_dir));
        mod.addIncludePath(b.path(imgui_dir ++ "/backends"));
        mod.linkFramework("MetalKit", .{});
        mod.linkFramework("GameController", .{});
        mod.linkSystemLibrary("c++", .{});

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
            compile.addFileArg(b.path(".zig-cache/wallify-imgui/" ++ source));
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
    const test_artifact = b.addTest(.{
        .root_module = mod,
    });
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);
}

fn linkMacos(module: *std.Build.Module) void {
    module.linkSystemLibrary("objc", .{});
    module.linkFramework("Foundation", .{});
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("CoreText", .{});
    module.linkFramework("AppKit", .{});
    module.linkFramework("CoreGraphics", .{});
}
