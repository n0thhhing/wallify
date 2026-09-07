const std = @import("std");

test {
    _ = @import("state.zig");
    _ = @import("ui/context_menu.zig");
    _ = @import("ui/hitbox.zig");
    _ = @import("ui/window.zig");
    _ = @import("media/playback_state.zig");
    _ = @import("media/playback_clock.zig");
    _ = @import("media/media.zig");
    _ = @import("media/spotify.zig");
    _ = @import("graphics/icon_transition.zig");
    _ = @import("graphics/pixel_engine.zig");
}
