const std = @import("std");
const hitbox = @import("hitbox.zig");

pub const ActionId = enum { PlayPause, Prev, Next };

pub const ButtonDef = struct {
    id: ActionId,
    name: []const u8,
    x: f64,
    y: f64,
    size: usize,

    pub fn bounds(self: ButtonDef) hitbox.Rect {
        const radius: f64 = if (self.id == .PlayPause) Layout.play_button_hit_radius else Layout.secondary_button_hit_radius;
        return .{
            .x = self.x - radius,
            .y = self.y - radius,
            .w = radius * 2,
            .h = radius * 2,
            .radius = radius,
        };
    }
};

pub const Layout = struct {
    // Core widget geometry consumed by rendering, hit-testing, and panel movement.
    pub const compact_content_width: f64 = 164.0;
    pub const compact_content_height: f64 = 164.0;
    pub const compact_panel_width: f64 = 180.0;
    pub const compact_panel_height: f64 = 224.0;
    pub const expanded_panel_width: f64 = 531.0;
    pub const expanded_panel_height: f64 = 199.0;

    pub const card_x_compact: f64 = 0.0;
    pub const card_x_expanded: f64 = 0.0;
    pub const card_y: f64 = 0.0;
    pub const card_radius: f64 = 26.0;

    pub const art_x_compact: f64 = 0.0;
    pub const art_x_expanded: f64 = 16.0;
    pub const art_y_compact: f64 = 0.0;
    pub const art_y_expanded: f64 = 16.0;
    pub const art_size_expanded: f64 = 136.0;
    pub const art_corner_radius_compact: f64 = 26.0;
    pub const art_corner_radius_expanded: f64 = 14.0;

    pub const bar_x_default: f64 = 170.0;
    pub const bar_y_default: f64 = 70.0;
    pub const button_y_default: f64 = 107.0;
    pub const min_bar_width: f64 = 80.0;
    pub const button_spacing: f64 = 41.0;
    pub const play_button_hit_radius: f64 = 20.0;
    pub const secondary_button_hit_radius: f64 = 15.0;

    pub const mini_text_width: f64 = 132.0;
    pub const mini_title_y: f64 = 116.0;
    pub const mini_artist_y: f64 = 137.0;

    pub const grid_pitch: f64 = 180.0;
    pub const grid_max: u8 = 20;
    pub const margin_left_default: i32 = 14;
    pub const margin_top_default: i32 = 12;
    pub const margin_top_min: i32 = -180;

    width: f64 = expanded_panel_width,
    height: f64 = expanded_panel_height,

    art_x: f64 = art_x_expanded,
    art_y: f64 = art_y_expanded,
    art_size: f64 = 152.0,

    bar_x: f64 = bar_x_default,
    bar_y: f64 = bar_y_default,
    bar_w: f64 = 360.0,
    bar_h: f64 = 5.0,
    bar_hit_pad_y: f64 = 14.0,

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 349.0, .y = 125.0, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 390.0, .y = 125.0, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 431.0, .y = 125.0, .size = 12.0 },
    },

    pub fn update(self: *Layout, panel_width: f64, panel_height: f64, mix: f64) void {
        self.width = panel_width;
        self.height = panel_height;
        self.art_x = art_x_compact + (art_x_expanded - art_x_compact) * mix;
        self.art_y = art_y_compact + (art_y_expanded - art_y_compact) * mix;
        self.art_size = compact_content_width + (art_size_expanded - compact_content_width) * mix;
        self.bar_x = bar_x_default;
        self.bar_y = bar_y_default;
        self.bar_w = @max(min_bar_width, panel_width - bar_x_default - 30);
        const center = self.bar_x + self.bar_w / 2;
        for (&self.buttons, 0..) |*button, i| {
            button.x = center + (@as(f64, @floatFromInt(i)) - 1) * button_spacing;
            button.y = button_y_default;
        }
    }

    pub fn card(self: Layout, mix: f64) hitbox.Rect {
        return .{
            .x = card_x_compact + (card_x_expanded - card_x_compact) * mix,
            .y = card_y,
            .w = compact_content_width + (self.width - compact_content_width) * mix,
            .h = compact_content_height,
            .radius = card_radius,
        };
    }
};

test "layout shares native geometry with rendered card and control hitboxes" {
    var value = Layout{};
    value.update(Layout.expanded_panel_width, Layout.expanded_panel_height, 1.0);
    const card = value.card(1.0);
    try std.testing.expectEqual(@as(f64, 531.0), card.w);
    try std.testing.expectEqual(@as(f64, 199.0), value.height);
    try std.testing.expectEqual(@as(f64, 164.0), card.h);
    try std.testing.expectEqual(@as(f64, 26.0), card.radius);
    try std.testing.expectEqual(@as(f64, 70.0), value.bar_y);
    try std.testing.expectEqual(@as(usize, 3), value.buttons.len);
    try std.testing.expect(value.buttons[1].bounds().contains(.{ .x = value.buttons[1].x, .y = value.buttons[1].y }));
}
