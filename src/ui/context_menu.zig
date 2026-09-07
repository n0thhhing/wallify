const std = @import("std");
const Point = @import("hitbox.zig").Point;

pub const Menu = struct {
    pub const width: f64 = 218;
    pub const height: f64 = 184;
    open: bool = false,
    x: f64 = 0,
    y: f64 = 0,
    hover: ?usize = null,
    pressed: ?usize = null,

    pub fn show(self: *Menu, point: Point, w: f64, h: f64) void {
        self.* = .{ .open = true, .x = std.math.clamp(point.x, 4, @max(4, w - width - 4)), .y = std.math.clamp(point.y, 4, @max(4, h - height - 4)) };
    }
    pub fn row(self: Menu, point: Point) ?usize {
        if (!self.open or point.x < self.x + 4 or point.x >= self.x + width - 4) return null;
        const y = point.y - self.y - 6;
        if (y < 0) return null;
        // A separator divides playback from preferences.
        if (y < 88) return @intFromFloat(@floor(y / 22));
        if (y < 104 or y >= 170) return null;
        return 4 + @as(usize, @intFromFloat(@floor((y - 104) / 22)));
    }
    pub fn rowY(self: Menu, index: usize) f64 {
        return self.y + 6 + @as(f64, @floatFromInt(index * 22)) + @as(f64, if (index >= 4) 16 else 0);
    }
    pub fn release(self: *Menu, point: Point) ?usize {
        const selected = self.row(point);
        const result = if (selected != null and selected == self.pressed) selected else null;
        self.pressed = null;
        if (result != null) self.open = false;
        return result;
    }
};

test "menu clamps inside widget and ignores separator" {
    var menu = Menu{};
    menu.show(.{ .x = 700, .y = 199 }, 708, 200);
    try std.testing.expectEqual(@as(f64, 486), menu.x);
    try std.testing.expectEqual(@as(f64, 12), menu.y);
    try std.testing.expectEqual(@as(?usize, null), menu.row(.{ .x = 500, .y = menu.y + 100 }));
    for (0..7) |i| try std.testing.expectEqual(@as(?usize, i), menu.row(.{ .x = 500, .y = menu.rowY(i) + 10 }));
}
test "only matching press and release selects an item" {
    var menu = Menu{};
    menu.show(.{ .x = 0, .y = 0 }, 708, 200);
    const p = Point{ .x = 20, .y = menu.rowY(2) + 10 };
    try std.testing.expectEqual(@as(?usize, null), menu.release(p));
    menu.pressed = 1;
    try std.testing.expectEqual(@as(?usize, null), menu.release(p));
    menu.pressed = 2;
    try std.testing.expectEqual(@as(?usize, 2), menu.release(p));
    try std.testing.expect(!menu.open);
}
