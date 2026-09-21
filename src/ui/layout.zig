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

const ModeGeometry = struct {
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
    buttons: [3]ButtonDef,
};

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

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 298.0, .y = 132.0, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 344.0, .y = 132.0, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 390.0, .y = 132.0, .size = 12.0 },
    },

    fn modeGeometry(mode: WidgetMode, width: f64, height: f64) ModeGeometry {
        const card_w = @max(0.0, width - 16.0);
        const card_h = @max(0.0, height - 16.0);

        return switch (mode) {
            .compact => .{
                // 1×1: artwork fills the card; metadata/control overlays sit over it.
                .art_x = 8.0,
                .art_y = 8.0,
                .art_size = @min(card_w, card_h),
                .art_radius = 26.0,
                .bar_x = 16.0,
                .bar_y = 112.0,
                .bar_w = @max(64.0, card_w - 32.0),
                .bar_h = 5.0,
                .text_x = 16.0,
                .text_width = @max(64.0, card_w - 32.0),
                .title_y = 116.0,
                .artist_y = 137.0,
                .timestamp_y = 99.0,
                .buttons = .{
                    .{ .id = .Prev, .name = "Action: Previous", .x = width / 2.0 - 46.0, .y = 48.0, .size = 12.0 },
                    .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = width / 2.0, .y = 48.0, .size = 14.0 },
                    .{ .id = .Next, .name = "Action: Next", .x = width / 2.0 + 46.0, .y = 48.0, .size = 12.0 },
                },
            },

            .two_by_one, .expanded => blk: {
                // 2×1 and 3×1 share the native horizontal player composition.
                const art_size = @min(132.0, @max(64.0, card_h - 32.0));
                const art_x = 24.0;
                const art_y = 8.0 + (card_h - art_size) / 2.0;
                const bar_x = 172.0;
                const bar_w = @max(min_bar_width, width - 196.0);
                const center = bar_x + bar_w / 2.0;
                break :blk .{
                    .art_x = art_x,
                    .art_y = art_y,
                    .art_size = art_size,
                    .art_radius = 14.0,
                    .bar_x = bar_x,
                    .bar_y = 84.0,
                    .bar_w = bar_w,
                    .bar_h = 5.0,
                    .text_x = bar_x,
                    .text_width = bar_w,
                    .title_y = 30.0,
                    .artist_y = 54.0,
                    .timestamp_y = 99.0,
                    .buttons = .{
                        .{ .id = .Prev, .name = "Action: Previous", .x = center - button_spacing, .y = 132.0, .size = 12.0 },
                        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = center, .y = 132.0, .size = 14.0 },
                        .{ .id = .Next, .name = "Action: Next", .x = center + button_spacing, .y = 132.0, .size = 12.0 },
                    },
                };
            },

            .one_by_two => blk: {
                // 1×2: artwork on top, metadata, progress, then controls.
                const inset = 16.0;
                const content_width = @max(0.0, width - 2.0 * inset);
                const controls_y = height - 48.0;
                const bar_y = controls_y - 60.0;
                const title_y = bar_y - 64.0;
                const art_y = 20.0;
                const art_size = @max(0.0, @min(148.0, @min(content_width, title_y - art_y - 20.0)));
                const art_x = (width - art_size) / 2.0;
                const center = width / 2.0;
                break :blk .{
                    .art_x = art_x,
                    .art_y = art_y,
                    .art_size = art_size,
                    .art_radius = 18.0,
                    .bar_x = inset,
                    .bar_y = bar_y,
                    .bar_w = content_width,
                    .bar_h = 5.0,
                    .text_x = inset,
                    .text_width = content_width,
                    .title_y = title_y,
                    .artist_y = title_y + 26.0,
                    .timestamp_y = bar_y + 12.0,
                    .buttons = .{
                        .{ .id = .Prev, .name = "Action: Previous", .x = center - button_spacing, .y = controls_y, .size = 12.0 },
                        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = center, .y = controls_y, .size = 14.0 },
                        .{ .id = .Next, .name = "Action: Next", .x = center + button_spacing, .y = controls_y, .size = 12.0 },
                    },
                };
            },

            .two_by_two => blk: {
                // 2×2: centered artwork with a full-width player footer.
                const inset = 24.0;
                const controls_y = height - 34.0;
                const bar_y = controls_y - 46.0;
                const title_y = bar_y - 52.0;
                const art_y = inset;
                const art_size = @max(0.0, @min(192.0, @min(width - 2.0 * inset, title_y - art_y - 12.0)));
                const art_x = (width - art_size) / 2.0;
                const center = width / 2.0;
                const content_width = @max(0.0, width - 2.0 * inset);
                break :blk .{
                    .art_x = art_x,
                    .art_y = art_y,
                    .art_size = art_size,
                    .art_radius = 26.0,
                    .bar_x = inset,
                    .bar_y = bar_y,
                    .bar_w = content_width,
                    .bar_h = 5.0,
                    .text_x = inset,
                    .text_width = content_width,
                    .title_y = title_y,
                    .artist_y = bar_y - 26.0,
                    .timestamp_y = bar_y + 12.0,
                    .buttons = .{
                        .{ .id = .Prev, .name = "Action: Previous", .x = center - button_spacing, .y = controls_y, .size = 12.0 },
                        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = center, .y = controls_y, .size = 14.0 },
                        .{ .id = .Next, .name = "Action: Next", .x = center + button_spacing, .y = controls_y, .size = 12.0 },
                    },
                };
            },
        };
    }

    fn lerp(a: f64, b: f64, t: f64) f64 {
        return a + (b - a) * t;
    }

    fn lerpButton(a: ButtonDef, b: ButtonDef, t: f64) ButtonDef {
        return .{
            .id = a.id,
            .name = a.name,
            .x = lerp(a.x, b.x, t),
            .y = lerp(a.y, b.y, t),
            .size = lerp(a.size, b.size, t),
        };
    }

    /// Updates responsive geometry while smoothly morphing between two form factors.
    pub fn update(
        self: *Layout,
        panel_width: f64,
        panel_height: f64,
        from_mode: WidgetMode,
        to_mode: WidgetMode,
        mix: f64,
    ) void {
        self.width = panel_width;
        self.height = panel_height;

        const t = std.math.clamp(mix, 0.0, 1.0);
        const from_size = from_mode.dimensions();
        const to_size = to_mode.dimensions();
        const from = modeGeometry(from_mode, from_size.width, from_size.height);
        const to = modeGeometry(to_mode, to_size.width, to_size.height);

        self.art_x = lerp(from.art_x, to.art_x, t);
        self.art_y = lerp(from.art_y, to.art_y, t);
        self.art_size = @max(1.0, lerp(from.art_size, to.art_size, t));
        self.art_radius = lerp(from.art_radius, to.art_radius, t);

        self.bar_x = lerp(from.bar_x, to.bar_x, t);
        self.bar_y = lerp(from.bar_y, to.bar_y, t);
        self.bar_w = @max(1.0, lerp(from.bar_w, to.bar_w, t));
        self.bar_h = lerp(from.bar_h, to.bar_h, t);

        self.text_x = lerp(from.text_x, to.text_x, t);
        self.text_width = @max(1.0, lerp(from.text_width, to.text_width, t));
        self.title_y = lerp(from.title_y, to.title_y, t);
        self.artist_y = lerp(from.artist_y, to.artist_y, t);
        self.timestamp_y = lerp(from.timestamp_y, to.timestamp_y, t);

        for (0..self.buttons.len) |i| {
            self.buttons[i] = lerpButton(from.buttons[i], to.buttons[i], t);
        }

        self.compact_mix =
            lerp(
                if (from_mode.isCompact()) 1.0 else 0.0,
                if (to_mode.isCompact()) 1.0 else 0.0,
                t,
            );
    }

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
