#ifndef WALLIFY_DEBUG_STATS_H
#define WALLIFY_DEBUG_STATS_H
#include <stdint.h>

typedef struct {
    int32_t glow, aurora, animations, dim, native_glass;
    int32_t hide_text, hide_progress, show_controls, timestamps;
    int32_t artwork_border, compact_gradient;
    int32_t frame, intensity, speed, source, mode, transition;
    int32_t font_scale, media_key_target, artwork_radius, progress_thickness;
    int32_t width, height, margin_left, margin_top, dragging;
    int64_t window_number, window_layer;
    double window_x, window_y, window_width, window_height;
    double outline_x, outline_y, outline_width, outline_height;
    uint32_t candidate_count;
    double snap_distance_sq;
    float mode_mix;
    uint32_t title_len, artist_len;
    char title[256], artist[256];
    double pointer_x, pointer_y;
    int32_t hover_target, click_target, seeking, panel_dragging;
    int32_t transition_active, frame_requested, has_artwork, snap_active;
    double layout_width, layout_height, compact_mix, transition_mix;
    double idle_mix, aurora_mix, artwork_mix, play_pause_mix;
    double position, duration, rate;
    double geometry[7][5];
    uint32_t geometry_visible[7];
} WallifyDebugSnapshot;

typedef struct {
    char device_name[128];
    uint32_t ready, profiling, pending, command_count, texture_count;
    uint64_t texture_bytes, scene_frames, rendered_frames, uploaded_bytes, draw_calls;
    double scene_ms, gpu_ms, logical_width, logical_height;
    double drawable_width, drawable_height, scale;
    uint32_t static_cache_valid, static_cache_rebuilds;
    double static_cache_width, static_cache_height;
} WallifyRendererStats;

#ifdef __cplusplus
extern "C" {
#endif
void wallify_debug_renderer_stats(WallifyRendererStats* out);
#ifdef __cplusplus
}
#endif
#endif
