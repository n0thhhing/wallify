const std = @import("std");

pub const PlaybackClock = struct {
    elapsed: f64 = 0,
    sampled_at: f64 = 0,
    rate: f64 = 0,
    correction: f64 = 0,

    pub fn position(self: PlaybackClock, now: f64, duration: f64) f64 {
        const dt = @max(0, now - self.sampled_at);
        const correction = self.correction * @max(0, 1 - dt / 0.4);
        return @min(@max(0, duration), @max(0, self.elapsed + dt * self.rate + correction));
    }

    pub fn sync(self: *PlaybackClock, elapsed: f64, rate: f64, now: f64, duration: f64, snap: bool) void {
        const previous = self.position(now, duration);
        const delta = previous - elapsed;
        self.* = .{ .elapsed = elapsed, .sampled_at = now, .rate = rate, .correction = if (!snap and @abs(delta) < 2) delta else 0 };
    }
};

test "progress advances between samples and stops while paused" {
    var clock = PlaybackClock{};
    clock.sync(42, 1, 10, 180, true);
    try std.testing.expectApproxEqAbs(@as(f64, 42.5), clock.position(10.5, 180), 0.001);
    clock.sync(42.5, 0, 10.5, 180, true);
    try std.testing.expectApproxEqAbs(@as(f64, 42.5), clock.position(20, 180), 0.001);
}

test "small corrections are continuous while seek and track changes snap" {
    var clock = PlaybackClock{};
    clock.sync(10, 1, 0, 180, true);
    clock.sync(10.9, 1, 1, 180, false);
    try std.testing.expectApproxEqAbs(@as(f64, 11), clock.position(1, 180), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 11.3), clock.position(1.4, 180), 0.001);
    clock.sync(90, 1, 2, 180, true);
    try std.testing.expectApproxEqAbs(@as(f64, 90), clock.position(2, 180), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 180), clock.position(200, 180), 0.001);
}
