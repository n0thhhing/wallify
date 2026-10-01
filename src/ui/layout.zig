const std = @import("std");
const hitbox = @import("hitbox.zig");

pub const ActionId = enum {
    Prev,
    PlayPause,
    Next,
};

pub const WidgetMode = enum(u8) {
    compact = 0, // 1×1
    two_by_one = 1, // 2×1
    expanded = 2, // 3×1
    one_by_two = 3, // 1×2
    two_by_two = 4, // 2×2

    pub fn dimensions(self: WidgetMode) struct { width: f64, height: f64 } {
        return switch (self) {
            .compact => .{ .width = 180.0, .height = 180.0 },
            .two_by_one => .{ .width = 360.0, .height = 180.0 },
            .expanded => .{ .width = 540.0, .height = 180.0 },
            .one_by_two => .{ .width = 180.0, .height = 360.0 },
            .two_by_two => .{ .width = 360.0, .height = 360.0 },
        };
    }

    pub fn isCompact(self: WidgetMode) bool {
        return self == .compact;
    }
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

const NativeGeometry = extern struct {
    art_x: f64,
    art_y: f64,
    art_size: f64,
    art_radius: f64,
    bar_x: f64,
    bar_y: f64,
    bar_w: f64,
    bar_h: f64,
    text_x: f64,
    text_width: f64,
    title_y: f64,
    artist_y: f64,
    timestamp_y: f64,
    button_center: f64,
    button_y: f64,
    compact_mix: f64,
};
extern fn wallify_layout_geometry(from_mode: c_int, to_mode: c_int, mix: f64, output: *NativeGeometry) callconv(.c) bool;

pub const Layout = struct {
    // Outer window sizes. One tile is 180×180 pt on the desktop grid.
    pub const compact_panel_width: f64 = 180.0;
    pub const compact_panel_height: f64 = 180.0;
    pub const medium_panel_width: f64 = 360.0;
    pub const expanded_panel_width: f64 = 540.0;
    pub const one_by_two_panel_width: f64 = 180.0;
    pub const one_by_two_panel_height: f64 = 360.0;
    pub const two_by_two_panel_width: f64 = 360.0;
    pub const two_by_two_panel_height: f64 = 360.0;
    pub const expanded_panel_height: f64 = 180.0;

    // Visual card dimensions and padding.
    pub const compact_content_width: f64 = 164.0;
    pub const compact_content_height: f64 = 164.0;
    pub const expanded_content_width: f64 = 524.0;
    pub const card_x_compact: f64 = 8.0;
    pub const card_x_expanded: f64 = 8.0;
    pub const card_y: f64 = 8.0;
    pub const card_radius: f64 = 26.0;

    // Desktop snapping grid.
    pub const grid_pitch: f64 = 180.0;
    pub const grid_max: u8 = 20;
    pub const margin_left_default: i32 = 8;
    pub const margin_top_default: i32 = 8;
    pub const margin_top_min: i32 = -180;

    pub const min_bar_width: f64 = 80.0;
    pub const button_spacing: f64 = 46.0;
    pub const play_button_hit_radius: f64 = 20.0;
    pub const secondary_button_hit_radius: f64 = 15.0;

    width: f64 = expanded_panel_width,
    height: f64 = expanded_panel_height,

    art_x: f64 = 24.0,
    art_y: f64 = 24.0,
    art_size: f64 = 132.0,
    art_radius: f64 = 14.0,

    bar_x: f64 = 172.0,
    bar_y: f64 = 84.0,
    bar_w: f64 = 344.0,
    bar_h: f64 = 5.0,
    bar_hit_pad_y: f64 = 14.0,

    text_x: f64 = 172.0,
    text_width: f64 = 344.0,
    title_y: f64 = 30.0,
    artist_y: f64 = 54.0,
    timestamp_y: f64 = 99.0,

    // 1.0 means compact/1×1 presentation, 0.0 means any non-compact form factor.
    compact_mix: f64 = 0.0,

    // Stable-frame geometry cache.
    cache_valid: bool = false,
    cache_width: f64 = 0.0,
    cache_height: f64 = 0.0,
    cache_from_mode: WidgetMode = .expanded,
    cache_to_mode: WidgetMode = .expanded,
    cache_mix: f64 = 0.0,

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 298.0, .y = 132.0, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 344.0, .y = 132.0, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 390.0, .y = 132.0, .size = 12.0 },
    },

    /// Updates responsive geometry while smoothly morphing between two form factors.
    // Layout is pure geometry: keeping this cache stable lets rendering skip all interpolation math
    // when neither the window size nor the active form-factor transition changed.
    pub fn update(
        self: *Layout,
        panel_width: f64,
        panel_height: f64,
        from_mode: WidgetMode,
        to_mode: WidgetMode,
        mix: f64,
    ) void {
        if (self.cache_valid and
            self.cache_width == panel_width and
            self.cache_height == panel_height and
            self.cache_from_mode == from_mode and
            self.cache_to_mode == to_mode and
            self.cache_mix == mix)
        {
            return;
        }

        self.width = panel_width;
        self.height = panel_height;

        var geometry: NativeGeometry = undefined;
        if (!wallify_layout_geometry(@intFromEnum(from_mode), @intFromEnum(to_mode), mix, &geometry)) return;
        self.art_x = geometry.art_x;
        self.art_y = geometry.art_y;
        self.art_size = geometry.art_size;
        self.art_radius = geometry.art_radius;
        self.bar_x = geometry.bar_x;
        self.bar_y = geometry.bar_y;
        self.bar_w = geometry.bar_w;
        self.bar_h = geometry.bar_h;
        self.text_x = geometry.text_x;
        self.text_width = geometry.text_width;
        self.title_y = geometry.title_y;
        self.artist_y = geometry.artist_y;
        self.timestamp_y = geometry.timestamp_y;
        self.compact_mix = geometry.compact_mix;
        for (&self.buttons, 0..) |*button, index| {
            button.x = geometry.button_center + (@as(f64, @floatFromInt(index)) - 1) * button_spacing;
            button.y = geometry.button_y;
        }

        self.cache_width = panel_width;
        self.cache_height = panel_height;
        self.cache_from_mode = from_mode;
        self.cache_to_mode = to_mode;
        self.cache_mix = mix;
        self.cache_valid = true;
    }

    // Keep the visual card inset from the window so the native glass/rim and hit testing share one boundary.
    pub fn card(self: Layout, _: f64) hitbox.Rect {
        return .{
            .x = 8.0,
            .y = 8.0,
            .w = @max(0.0, self.width - 16.0),
            .h = @max(0.0, self.height - 16.0),
            .radius = card_radius,
        };
    }

    pub fn controlsVisible(self: Layout, enabled: bool) bool {
        return enabled and self.compact_mix <= 0.5;
    }

    pub fn progressVisible(self: Layout, hidden: bool) bool {
        return !hidden and self.compact_mix <= 0.5;
    }
};

test "compact layouts and disabled controls have no playback targets" {
    var layout = Layout{};
    try std.testing.expect(layout.controlsVisible(true));
    try std.testing.expect(!layout.controlsVisible(false));
    try std.testing.expect(layout.progressVisible(false));
    try std.testing.expect(!layout.progressVisible(true));
    layout.compact_mix = 1.0;
    try std.testing.expect(!layout.controlsVisible(true));
    try std.testing.expect(!layout.progressVisible(false));
    layout.compact_mix = 0.5;
    try std.testing.expect(layout.controlsVisible(true));
}

test "vertical layouts share a centerline and separate seek and controls" {
    for ([_]WidgetMode{ .one_by_two, .two_by_two }) |mode| {
        const dimensions = mode.dimensions();
        var layout = Layout{};
        layout.update(dimensions.width, dimensions.height, mode, mode, 1);
        const center = layout.width / 2;
        try std.testing.expectEqual(center, layout.art_x + layout.art_size / 2);
        try std.testing.expectEqual(center, layout.text_x + layout.text_width / 2);
        try std.testing.expectEqual(center, layout.bar_x + layout.bar_w / 2);
        try std.testing.expectEqual(center, layout.buttons[1].x);
        try std.testing.expect(layout.art_y + layout.art_size + 12 <= layout.title_y);
        const seek_bottom = layout.bar_y + layout.bar_h + layout.bar_hit_pad_y;
        for (layout.buttons) |button| {
            const bounds = button.bounds();
            try std.testing.expect(seek_bottom < bounds.y);
            try std.testing.expect(bounds.y + bounds.h <= layout.height - 8);
            try std.testing.expect(bounds.x >= 8);
            try std.testing.expect(bounds.x + bounds.w <= layout.width - 8);
        }
    }
}

test "form factors use exact desktop grid dimensions" {
    const one = WidgetMode.compact.dimensions();
    try std.testing.expectEqual(@as(f64, 180.0), one.width);
    try std.testing.expectEqual(@as(f64, 180.0), one.height);

    const two = WidgetMode.two_by_one.dimensions();
    try std.testing.expectEqual(@as(f64, 360.0), two.width);
    try std.testing.expectEqual(@as(f64, 180.0), two.height);

    const three = WidgetMode.expanded.dimensions();
    try std.testing.expectEqual(@as(f64, 540.0), three.width);
    try std.testing.expectEqual(@as(f64, 180.0), three.height);

    const vertical = WidgetMode.one_by_two.dimensions();
    try std.testing.expectEqual(@as(f64, 180.0), vertical.width);
    try std.testing.expectEqual(@as(f64, 360.0), vertical.height);

    const square = WidgetMode.two_by_two.dimensions();
    try std.testing.expectEqual(@as(f64, 360.0), square.width);
    try std.testing.expectEqual(@as(f64, 360.0), square.height);
}

test "layout produces exact card bounds for every form factor" {
    var value = Layout{};
    const modes = [_]WidgetMode{ .compact, .two_by_one, .expanded, .one_by_two, .two_by_two };

    for (modes) |mode| {
        const size = mode.dimensions();
        value.update(size.width, size.height, mode, mode, 1.0);
        const card = value.card(1.0);
        try std.testing.expectEqual(size.width - 16.0, card.w);
        try std.testing.expectEqual(size.height - 16.0, card.h);
    }
}

test "mode transitions interpolate artwork and input geometry together" {
    var value = Layout{};
    value.update(360, 180, .compact, .expanded, 0.5);
    try std.testing.expectEqual(@as(f64, 16), value.art_x);
    try std.testing.expectEqual(@as(f64, 148), value.art_size);
    try std.testing.expectEqual(@as(f64, 94), value.bar_x);
    try std.testing.expectEqual(@as(f64, 217), value.buttons[1].x);
    try std.testing.expectEqual(@as(f64, 90), value.buttons[1].y);
    try std.testing.expectEqual(@as(f64, 0.5), value.compact_mix);
    try std.testing.expect(value.controlsVisible(true));
    value.update(540, 180, .compact, .expanded, 2);
    try std.testing.expectEqual(@as(f64, 344), value.buttons[1].x);
    try std.testing.expectEqual(@as(f64, 132), value.art_size);
    value.update(180, 180, .compact, .expanded, -1);
    try std.testing.expectEqual(@as(f64, 90), value.buttons[1].x);
    try std.testing.expectEqual(@as(f64, 164), value.art_size);
    try std.testing.expect(!value.controlsVisible(true));
}
