#pragma once
#import <AppKit/AppKit.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool glow;
    bool aurora;
    bool animations;
    bool dim_paused;
    bool debug_hud;
    int frame_strength;   // 0: off, 1: subtle, 2: strong
    int glow_intensity;   // 0: low, 1: normal, 2: high
    int animation_speed;  // 0: slow, 1: normal, 2: fast
    int media_source;     // 0: now_playing, 1: spotify
    int widget_mode;      // 0: compact, 1: expanded
    int idle_style;       // 0: pixel_cat, 1: banana_cat, 2: spotify
    int track_transition; // 0: default, 1: cinematic, 2: ripple, 3: flip, 4: vinyl, 5: glitch
    int margin_left;
    int margin_top;
    int grid_x;
    int grid_y;
} WallifySettingsSnapshot;

// Exported from Zig
extern void wallify_settings_get_snapshot(WallifySettingsSnapshot *out_snapshot);
extern void wallify_settings_apply_bool(int key, bool val);
extern void wallify_settings_apply_int(int key, int val);
extern void wallify_settings_restore_defaults(void);
extern void wallify_settings_reset_position(void);

// Exported to Zig & native AppKit menu handlers
void wallify_show_settings_window(void);
void wallify_close_settings_window(void);
bool wallify_has_settings_flag(void);
void wallify_settings_notify_position_changed(void);

#ifdef __cplusplus
}
#endif
