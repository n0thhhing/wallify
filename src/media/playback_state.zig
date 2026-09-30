const std = @import("std");

// Reconcile asynchronous snapshots with the latest local playback intent.
pub const PlaybackState = struct {
    pending: ?bool = null,
    deadline: f64 = 0,
    confirmed_since: ?f64 = null,

    pub fn request(self: *PlaybackState, playing: bool, now: f64) void {
        self.* = .{ .pending = playing, .deadline = now + 1.5 };
    }

    pub fn accept(self: *PlaybackState, playing: bool, current: bool, now: f64, track_changed: bool) bool {
        if (track_changed) {
            self.* = .{};
            return true;
        }
        if (self.pending) |expected| {
            if (playing == expected) {
                if (self.confirmed_since == null) self.confirmed_since = now;
                if (now >= self.deadline and now - self.confirmed_since.? >= 0.4) self.pending = null;
                return true;
            }
            self.confirmed_since = null;
            if (now < self.deadline) return false;
            self.pending = null; // A failed command must eventually reconcile.
        }
        _ = current;
        // External changes have no local intent to protect. Waiting for a second
        // snapshot adds the source's entire fallback interval to pause/play.
        return true;
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
