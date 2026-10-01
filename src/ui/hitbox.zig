const std = @import("std");
extern fn wallify_rounded_contains(x: f64, y: f64, width: f64, height: f64, radius: f64, px: f64, py: f64) callconv(.c) bool;

pub const Point = struct { x: f64, y: f64 };
pub const Rect = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    radius: f64 = 0,

    pub fn contains(self: Rect, p: Point) bool {
        return wallify_rounded_contains(self.x, self.y, self.w, self.h, self.radius, p.x, p.y);
    }
};

test "rounded hitboxes exclude corners and use half-open edges" {
    const box = Rect{ .x = 10, .y = 20, .w = 46, .h = 46, .radius = 14 };
    try std.testing.expect(box.contains(.{ .x = 33, .y = 43 }));
    try std.testing.expect(!box.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(!box.contains(.{ .x = 56, .y = 43 }));
    try std.testing.expect(box.contains(.{ .x = 10, .y = 43 }));
}

test "zero-radius rectangle behaves as half-open axis aligned box" {
    const box = Rect{ .x = 10, .y = 20, .w = 30, .h = 40, .radius = 0 };
    try std.testing.expect(box.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(box.contains(.{ .x = 39.9, .y = 59.9 }));
    try std.testing.expect(!box.contains(.{ .x = 40, .y = 30 }));
    try std.testing.expect(!box.contains(.{ .x = 20, .y = 60 }));
    try std.testing.expect(!box.contains(.{ .x = 9.9, .y = 20 }));
}

test "invalid and empty hitboxes never accept a pointer" {
    try std.testing.expect(!(Rect{ .x = 0, .y = 0, .w = 0, .h = 40 }).contains(.{ .x = 0, .y = 20 }));
    try std.testing.expect(!(Rect{ .x = 0, .y = 0, .w = 40, .h = 40 }).contains(.{ .x = std.math.nan(f64), .y = 20 }));
}
