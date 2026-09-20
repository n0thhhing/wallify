const std = @import("std");
const hitbox = @import("hitbox.zig");

pub const ActionId = enum {
    Prev,
    PlayPause,
    Next,
};

pub const ButtonDef = struct {
    id: ActionId,
    name: []const u8,
    x: f64,
    y: f64,
    size: f64,

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

/// Core widget geometry consumed by rendering, hit-testing, and widget movement.
///
/// ## Visual Architecture
/// - **macOS Widget Grid Standard**:
/// - Compact mode uses an outer window of **180.0 × 180.0 pt** (`Layout.compact_panel_width/height`).
/// - Expanded mode uses an outer window of **540.0 × 180.0 pt** (exactly 3 columns × 1 row on the 180pt grid).
/// - The visible frosted card inside has an **8.0 pt transparent margin** on all sides (`card_x = 8.0`, `card_y = 8.0`):
///   - Compact card: **164.0 × 164.0 pt**, corner radius **26.0 pt**.
///   - Expanded card: **524.0 × 164.0 pt**, corner radius **26.0 pt**.
/// - When two widgets sit adjacent on the 180pt grid, their outer window boundaries touch (`180 - 164 = 16 pt`),
///   producing the signature uniform **16.0 pt visual gutter** between cards (`8.0 pt + 8.0 pt = 16.0 pt`).
pub const Layout = struct {
    // Window dimensions (outer borderless window)
    pub const compact_panel_width: f64 = 180.0;
    pub const compact_panel_height: f64 = 180.0;
    pub const medium_panel_width: f64 = 360.0;
    pub const expanded_panel_width: f64 = 540.0;
    pub const wide_panel_width: f64 = 720.0;
    pub const expanded_panel_height: f64 = 180.0;

    // Visual card dimensions and padding
    pub const compact_content_width: f64 = 164.0;
    pub const compact_content_height: f64 = 164.0;
    pub const expanded_content_width: f64 = 524.0;
    pub const card_x_compact: f64 = 8.0;
    pub const card_x_expanded: f64 = 8.0;
    pub const card_y: f64 = 8.0;
    pub const card_radius: f64 = 26.0;

    // Artwork positioning (uniform 16.0 pt margin from card top, left, bottom, and to the text column)
    pub const art_x_compact: f64 = 8.0;
    pub const art_x_expanded: f64 = 24.0;
    pub const art_y_compact: f64 = 8.0;
    pub const art_y_expanded: f64 = 24.0;
    pub const art_size_expanded: f64 = 132.0;
    pub const art_corner_radius_compact: f64 = 26.0;
    pub const art_corner_radius_expanded: f64 = 14.0;

    // Playback bar and control dimensions (uniform 16.0 pt gutter from artwork and 16.0 pt margin to right card edge)
    pub const bar_x_default: f64 = 172.0;
    pub const bar_y_default: f64 = 84.0;
    pub const button_y_default: f64 = 132.0;
    pub const min_bar_width: f64 = 80.0;
    pub const button_spacing: f64 = 46.0;
    pub const play_button_hit_radius: f64 = 20.0;
    pub const secondary_button_hit_radius: f64 = 15.0;

    // Compact mode text positioning
    pub const mini_text_width: f64 = 132.0;
    pub const mini_title_y: f64 = 116.0;
    pub const mini_artist_y: f64 = 137.0;

    // Desktop snapping grid configuration
    pub const grid_pitch: f64 = 180.0;
    pub const grid_max: u8 = 20;
    pub const margin_left_default: i32 = 8;
    pub const margin_top_default: i32 = 8;
    pub const margin_top_min: i32 = -180;

    width: f64 = expanded_panel_width,
    height: f64 = expanded_panel_height,

    art_x: f64 = art_x_expanded,
    art_y: f64 = art_y_expanded,
    art_size: f64 = 152.0,

    bar_x: f64 = bar_x_default,
    bar_y: f64 = bar_y_default,
    bar_w: f64 = 344.0,
    bar_h: f64 = 5.0,
    bar_hit_pad_y: f64 = 14.0,

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 298.0, .y = button_y_default, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 344.0, .y = button_y_default, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 390.0, .y = button_y_default, .size = 12.0 },
    },

    /// Updates dynamic element positions (e.g. seek bar and control buttons) based on current widget size and mode mix.
    pub fn update(self: *Layout, panel_width: f64, panel_height: f64, mix: f64) void {
        self.width = panel_width;
        self.height = panel_height;
        self.art_x = art_x_compact + (art_x_expanded - art_x_compact) * mix;
        self.art_y = art_y_compact + (art_y_expanded - art_y_compact) * mix;
        self.art_size = compact_content_width + (art_size_expanded - compact_content_width) * mix;
        self.bar_x = bar_x_default;
        self.bar_y = bar_y_default;
        self.bar_w = @max(min_bar_width, panel_width - bar_x_default - 24.0);
        const center = self.bar_x + self.bar_w / 2;
        for (&self.buttons, 0..) |*button, i| {
            button.x = center + (@as(f64, @floatFromInt(i)) - 1) * button_spacing;
            button.y = button_y_default;
        }
    }

    /// Calculates the rounded card rectangle for hit testing and rendering, smoothly interpolated between compact and expanded modes.
    pub fn card(self: Layout, mix: f64) hitbox.Rect {
        return .{
            .x = card_x_compact + (card_x_expanded - card_x_compact) * mix,
            .y = card_y,
            .w = compact_content_width + (self.width - compact_content_width - card_x_compact * 2.0) * mix,
            .h = compact_content_height,
            .radius = card_radius,
        };
    }
};

test "layout shares native geometry with rendered card and control hitboxes" {
    var value = Layout{};
    value.update(Layout.expanded_panel_width, Layout.expanded_panel_height, 1.0);
    const card = value.card(1.0);
    try std.testing.expectEqual(@as(f64, 524.0), card.w);
    try std.testing.expectEqual(@as(f64, 180.0), value.height);
    try std.testing.expectEqual(@as(f64, 164.0), card.h);
    try std.testing.expectEqual(@as(f64, 26.0), card.radius);
    try std.testing.expect(value.bar_y == Layout.bar_y_default);
    try std.testing.expectEqual(@as(usize, 3), value.buttons.len);
    try std.testing.expect(value.buttons[1].bounds().contains(.{ .x = value.buttons[1].x, .y = value.buttons[1].y }));
}

test "compact card maintains uniform 8pt insets within 180x180 tile" {
    var value = Layout{};
    value.update(Layout.compact_panel_width, Layout.compact_panel_height, 0.0);
    const card = value.card(0.0);
    try std.testing.expectEqual(@as(f64, 8.0), card.x);
    try std.testing.expectEqual(@as(f64, 8.0), card.y);
    try std.testing.expectEqual(@as(f64, 164.0), card.w);
    try std.testing.expectEqual(@as(f64, 164.0), card.h);
}
