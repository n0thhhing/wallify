pub const SpotifyControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

pub extern "c" fn widget_spotify_observe() void;
pub extern "c" fn widget_spotify_take_state() c_int;
pub extern "c" fn widget_spotify_wait_for_event(timeout_ms: u64) c_int;
pub extern "c" fn widget_spotify_set_helper_pid(pid: c_int) void;
pub extern "c" fn widget_open_spotify() void;
pub extern "c" fn widget_is_spotify_running() c_int;
pub extern "c" fn widget_spotify_control(cmd: SpotifyControl) void;
pub extern "c" fn widget_spotify_seek(position: f64) void;
pub extern "c" fn widget_query_spotify(buf: [*]u8, max_len: usize) usize;
