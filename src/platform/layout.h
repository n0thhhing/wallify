#pragma once
#include <stdbool.h>
typedef struct { double x, y, w, h, radius; } WallifyCardRect;
typedef struct {
    double art_x, art_y, art_size, art_radius;
    double bar_x, bar_y, bar_w, bar_h;
    double text_x, text_width, title_y, artist_y, timestamp_y;
    double button_center, button_y, compact_mix;
} WallifyLayoutGeometry;
typedef struct {
    WallifyCardRect card, art, bar, buttons[3], title, artist;
    double bar_x, bar_width;
    bool controls_visible, progress_visible;
} WallifyInputGeometry;
