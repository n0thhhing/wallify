const std = @import("std");

// Reconcile asynchronous snapshots with the latest local playback intent.
extern fn wallify_playback_request(intent: *PlaybackState, playing: bool, now: f64) callconv(.c) void;
extern fn wallify_playback_accept(intent: *PlaybackState, playing: bool, now: f64, track_changed: bool) callconv(.c) bool;

pub const PlaybackState = extern struct {
    pending: c_int = -1,
    deadline: f64 = 0,
    confirmed_since: f64 = -1,

    pub fn request(self: *PlaybackState, playing: bool, now: f64) void {
        wallify_playback_request(self, playing, now);
    }

    pub fn accept(self: *PlaybackState, playing: bool, current: bool, now: f64, track_changed: bool) bool {
        _ = current;
        return wallify_playback_accept(self, playing, now, track_changed);
    }
};

test "play confirmation followed by stale pause cannot rubberband" {
    var state = PlaybackState{};
    state.request(true, 0);
    try std.testing.expect(state.accept(true, true, 0.1, false));
    try std.testing.expect(!state.accept(false, true, 0.2, false));
    try std.testing.expect(!state.accept(false, true, 0.5, false));
    try std.testing.expect(state.accept(true, true, 0.6, false));
    try std.testing.expect(state.accept(true, true, 1.01, false));
    try std.testing.expect(!state.accept(false, true, 1.1, false));
    try std.testing.expect(state.accept(true, true, 1.2, false));
}

test "external pause and play are accepted on the first snapshot" {
    var state = PlaybackState{};
    try std.testing.expect(state.accept(false, true, 0, false));
    try std.testing.expect(state.accept(true, false, 0.01, false));
}

test "failed commands recover and latest request wins" {
    var state = PlaybackState{};
    state.request(true, 0);
    try std.testing.expect(!state.accept(false, true, 1, false));
    try std.testing.expect(state.accept(false, true, 1.6, false));
    try std.testing.expect(state.accept(false, true, 1.81, false));
    state.request(true, 2);
    state.request(false, 2.1);
    try std.testing.expect(!state.accept(true, false, 2.2, false));
    try std.testing.expect(state.accept(false, false, 2.3, false));
    try std.testing.expect(state.accept(true, false, 2.4, true));
}
