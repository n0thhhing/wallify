const std = @import("std");

pub const MediaRemoteCommand = enum(u32) {
    play = 0,
    pause = 1,
    toggle_play_pause = 2,
    stop = 3,
    next_track = 4,
    previous_track = 5,
};

const FRAMEWORK_PATH = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";

pub fn sendCommand(cmd: MediaRemoteCommand) void {
    var lib = std.DynLib.open(FRAMEWORK_PATH) catch return;
    defer lib.close();
    if (lib.lookup(*const fn (c_uint, ?*anyopaque) callconv(.c) void, "MRMediaRemoteSendCommand")) |send_func| {
        send_func(@intFromEnum(cmd), null);
    }
}

pub fn setElapsedTime(target: f64) void {
    var lib = std.DynLib.open(FRAMEWORK_PATH) catch return;
    defer lib.close();
    if (lib.lookup(*const fn (f64) callconv(.c) void, "MRMediaRemoteSetElapsedTime")) |set_func| {
        set_func(target);
    }
}
