pub const MediaRemoteCommand = enum(u32) {
    play = 0,
    pause = 1,
    toggle_play_pause = 2,
    stop = 3,
    next_track = 4,
    previous_track = 5,
};

extern fn wallify_system_media_command(command: u32) void;
extern fn wallify_system_media_seek(elapsed: f64) void;

pub fn sendCommand(cmd: MediaRemoteCommand) void {
    wallify_system_media_command(@intFromEnum(cmd));
}

pub fn setElapsedTime(target: f64) void {
    wallify_system_media_seek(target);
}
