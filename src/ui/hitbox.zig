const std = @import("std");

pub const Point = struct { x: f64, y: f64 };
pub const Rect = struct {
    x: f64, y: f64, w: f64, h: f64, radius: f64 = 0,

    pub fn contains(self: Rect, p: Point) bool {
        if (p.x < self.x or p.y < self.y or p.x >= self.x + self.w or p.y >= self.y + self.h) return false;
        const radius = @min(self.radius, @min(self.w, self.h) / 2);
        const dx = @max(@max(self.x + radius - p.x, p.x - (self.x + self.w - radius)), 0);
        const dy = @max(@max(self.y + radius - p.y, p.y - (self.y + self.h - radius)), 0);
        return dx * dx + dy * dy <= radius * radius;
    }
};

// SGR coordinates are one-based cells. Use their centers, in the exact
// coordinate space used by the Kitty image's c/r placement dimensions.
pub fn fromCell(col: u32, row: u32, cell_w: f64, cell_h: f64) Point {
    if (col == 0 or row == 0) return .{ .x = -1, .y = -1 };
    return .{ .x = (@as(f64, @floatFromInt(col)) - 0.5) * cell_w,
              .y = (@as(f64, @floatFromInt(row)) - 0.5) * cell_h };
}

test "rounded hitboxes exclude corners and use half-open edges" {
    const box = Rect{ .x = 10, .y = 20, .w = 46, .h = 46, .radius = 14 };
    try std.testing.expect(box.contains(.{ .x = 33, .y = 43 }));
    try std.testing.expect(!box.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(!box.contains(.{ .x = 56, .y = 43 }));
    try std.testing.expect(box.contains(.{ .x = 10, .y = 43 }));
}

test "cell mapping follows image scaling and rejects invalid coordinates" {
    const p = fromCell(46, 10, 600.0 / 70.0, 200.0 / 12.0);
    try std.testing.expectApproxEqAbs(@as(f64, 390), p.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 158.333333), p.y, 0.001);
    try std.testing.expect(fromCell(0, 1, 10, 20).x < 0);
}


pub fn fromPixel(x: u32, y: u32, display_w: f64, display_h: f64, logical_w: f64, logical_h: f64) Point {
    if (x == 0 or y == 0 or display_w <= 0 or display_h <= 0) return .{ .x = -1, .y = -1 };
    return .{ .x = (@as(f64, @floatFromInt(x)) - 1) * logical_w / display_w,
              .y = (@as(f64, @floatFromInt(y)) - 1) * logical_h / display_h };
}

test "pixel mapping matches scaled display and exact circle boundaries" {
    const center = fromPixel(901, 321, 1200, 400, 600, 200);
    const circle = Rect{ .x = 432, .y = 142, .w = 36, .h = 36, .radius = 18 };
    try std.testing.expect(circle.contains(center));
    try std.testing.expect(circle.contains(fromPixel(935, 321, 1200, 400, 600, 200)));
    try std.testing.expect(!circle.contains(fromPixel(937, 321, 1200, 400, 600, 200)));
    try std.testing.expect(!circle.contains(.{ .x = 433, .y = 143 }));
}

test "zero-radius rectangle behaves as half-open axis aligned box" {
    const box = Rect{ .x = 10, .y = 20, .w = 30, .h = 40, .radius = 0 };
    try std.testing.expect(box.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(box.contains(.{ .x = 39.9, .y = 59.9 }));
    try std.testing.expect(!box.contains(.{ .x = 40, .y = 30 }));
    try std.testing.expect(!box.contains(.{ .x = 20, .y = 60 }));
    try std.testing.expect(!box.contains(.{ .x = 9.9, .y = 20 }));
}

test "fromPixel rejects zero and non-positive display dimensions" {
    try std.testing.expectEqual(@as(f64, -1), fromPixel(0, 10, 100, 100, 50, 50).x);
    try std.testing.expectEqual(@as(f64, -1), fromPixel(10, 0, 100, 100, 50, 50).y);
    try std.testing.expectEqual(@as(f64, -1), fromPixel(10, 10, 0, 100, 50, 50).x);
    try std.testing.expectEqual(@as(f64, -1), fromPixel(10, 10, 100, -10, 50, 50).y);
}
