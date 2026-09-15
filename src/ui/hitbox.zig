const std = @import("std");

pub const Point = struct { x: f64, y: f64 };
pub const Rect = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    radius: f64 = 0,

    pub fn contains(self: Rect, p: Point) bool {
        if (p.x < self.x or p.y < self.y or p.x >= self.x + self.w or p.y >= self.y + self.h) return false;
        const radius = @min(self.radius, @min(self.w, self.h) / 2);
        const dx = @max(@max(self.x + radius - p.x, p.x - (self.x + self.w - radius)), 0);
        const dy = @max(@max(self.y + radius - p.y, p.y - (self.y + self.h - radius)), 0);
        return dx * dx + dy * dy <= radius * radius;
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
