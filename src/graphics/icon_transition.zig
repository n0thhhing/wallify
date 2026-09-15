const std = @import("std");

const SWAP_PROGRESS: f64 = 0.5;
const SWAP_DURATION: f64 = 0.18;
const EXPANSION_DURATION: f64 = 0.48;


// Measured from the supplied recording: a brief contraction, a visible
// half-size replacement, then a longer ease-out expansion. No empty frame.
pub fn scale(mix: f64, playing: bool) f64 {
    const progress = if (playing) mix else 1 - mix;
    if (progress < SWAP_PROGRESS) {
        const t = progress / SWAP_PROGRESS;
        return 1 - 0.5 * t * t;
    }
    const remaining = (1 - progress) / SWAP_PROGRESS;
    return 1 - 0.5 * remaining * remaining * remaining;
}

pub fn advance(mix: f64, playing: bool, dt: f64) f64 {
    var progress = if (playing) mix else 1 - mix;
    var remaining = @max(0, dt);
    if (progress < SWAP_PROGRESS) {
        const used = @min(remaining, (SWAP_PROGRESS - progress) * SWAP_DURATION);
        progress += used / SWAP_DURATION; // 90 ms to the swap
        remaining -= used;
    }
    progress = @min(1, progress + remaining / EXPANSION_DURATION); // 240 ms expansion
    return if (playing) progress else 1 - progress;
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
