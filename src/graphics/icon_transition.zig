const std = @import("std");

extern fn wallify_icon_scale(mix: f64, playing: bool) callconv(.c) f64;
extern fn wallify_icon_advance(mix: f64, playing: bool, dt: f64) callconv(.c) f64;

pub fn scale(mix: f64, playing: bool) f64 {
    return wallify_icon_scale(mix, playing);
}
pub fn advance(mix: f64, playing: bool, dt: f64) f64 {
    return wallify_icon_advance(mix, playing, dt);
}

test "both transitions stay visible and finish at full size" {
    for ([_]bool{ false, true }) |playing| {
        var mix: f64 = if (playing) 0 else 1;
        for (0..30) |_| {
            try std.testing.expect(scale(mix, playing) >= 0.5);
            try std.testing.expect(scale(mix, playing) <= 1);
            mix = advance(mix, playing, 1.0 / 60.0);
        }
        try std.testing.expectEqual(@as(f64, if (playing) 1 else 0), mix);
        try std.testing.expectEqual(@as(f64, 1), scale(mix, playing));
    }
}

test "uneven frame intervals retain transition timing" {
    const mix = advance(0, true, 0.09);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), mix, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), scale(mix, true), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), advance(mix, true, 0.24), 0.0001);
}
