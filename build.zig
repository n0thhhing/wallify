const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build the metadata_fetcher.dylib for Perl
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

    // 2. Build the main spotify-player (Pure Zig)
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.linkSystemLibrary("objc", .{});
    mod.linkFramework("CoreFoundation", .{});
    mod.linkFramework("CoreText", .{});
    mod.linkFramework("AppKit", .{});
    mod.linkFramework("CoreGraphics", .{});
    mod.addCSourceFile(.{ .file = b.path("src/snap.m"), .flags = &[_][]const u8{"-fobjc-arc"} });

    const exe = b.addExecutable(.{
        .name = "spotify-player",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the player");
    run_step.dependOn(b.getInstallStep());
    run_step.dependOn(&b.addRunArtifact(exe).step);
}
