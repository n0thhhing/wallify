pub const IconKind = enum(c_int) {
    play = 0,
    pause = 1,
    prev = 2,
    next = 3,
};

pub extern "c" fn widget_icon(pixels: [*]u32, width: usize, height: usize, x: f64, y: f64, kind: IconKind, hover: f64, opacity: f64, scale: f64) void;
pub extern "c" fn widget_spotify_icon(pixels: [*]u32, width: usize, height: usize, x: f64, y: f64, size: f64) c_int;
