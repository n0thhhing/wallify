const std = @import("std");
const Point = @import("hitbox.zig").Point;

pub const MenuItem = enum(usize) {
    play_pause = 0,
    previous_track = 1,
    next_track = 2,
    open_spotify = 3,
    artwork_glow = 4,
    animations = 5,
    dim_artwork = 6,
};

pub const Menu = struct {
    pub const width: f64 = 218;
    pub const height: f64 = 184;
    open: bool = false,
    x: f64 = 0,
    y: f64 = 0,
    hover: ?MenuItem = null,
    pressed: ?MenuItem = null,

    pub fn show(self: *Menu, point: Point, w: f64, h: f64) void {
        self.* = .{ .open = true, .x = std.math.clamp(point.x, 4, @max(4, w - width - 4)), .y = std.math.clamp(point.y, 4, @max(4, h - height - 4)) };
    }
    pub fn row(self: Menu, point: Point) ?MenuItem {
        if (!self.open or point.x < self.x + 4 or point.x >= self.x + width - 4) return null;
        const y = point.y - self.y - 6;
        if (y < 0) return null;
        // A separator divides playback from preferences.
        if (y < 88) {
            const idx: usize = @intFromFloat(@floor(y / 22));
            return if (idx < 4) @enumFromInt(idx) else null;
        }
        if (y < 104 or y >= 170) return null;
        const idx: usize = 4 + @as(usize, @intFromFloat(@floor((y - 104) / 22)));
        return if (idx <= 6) @enumFromInt(idx) else null;
    }
    pub fn rowY(self: Menu, item: MenuItem) f64 {
        const index = @intFromEnum(item);
        return self.y + 6 + @as(f64, @floatFromInt(index * 22)) + @as(f64, if (index >= 4) 16 else 0);
    }
    pub fn release(self: *Menu, point: Point) ?MenuItem {
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
    try std.testing.expectEqual(@as(?MenuItem, null), menu.row(.{ .x = 500, .y = menu.y + 100 }));
    inline for (std.meta.tags(MenuItem)) |item| {
        try std.testing.expectEqual(@as(?MenuItem, item), menu.row(.{ .x = 500, .y = menu.rowY(item) + 10 }));
    }
}
test "only matching press and release selects an item" {
    var menu = Menu{};
    menu.show(.{ .x = 0, .y = 0 }, 708, 200);
    const p = Point{ .x = 20, .y = menu.rowY(.next_track) + 10 };
    try std.testing.expectEqual(@as(?MenuItem, null), menu.release(p));
    menu.pressed = .previous_track;
    try std.testing.expectEqual(@as(?MenuItem, null), menu.release(p));
    menu.pressed = .next_track;
    try std.testing.expectEqual(@as(?MenuItem, .next_track), menu.release(p));
    try std.testing.expect(!menu.open);
}
