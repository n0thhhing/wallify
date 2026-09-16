#ifndef WALLIFY_GPU_H
#define WALLIFY_GPU_H
// Shared verbatim by Zig (@cImport), Objective-C, and Metal. Logical points.
#define WALLIFY_MAX_COMMANDS 128
#define WALLIFY_MAX_TEXTURES 64
#define WALLIFY_SOLID 0
#define WALLIFY_TEXTURE 1
#define WALLIFY_GRADIENT 2
#define WALLIFY_GLOW 3
#define WALLIFY_NEAREST 4
#define WALLIFY_GLOW_SOURCE 5
#define WALLIFY_GLASS 6
#define WALLIFY_SHADOW 7
#define WALLIFY_AURORA 8
#define WALLIFY_CINEMATIC 9
#define WALLIFY_RIPPLE 10
#define WALLIFY_FLIP 11
#define WALLIFY_VINYL 12
#define WALLIFY_GLITCH 13
#define WALLIFY_GLOW_BLUR 40.0f
#define WALLIFY_GLOW_SCALE_X 1.3f
#define WALLIFY_GLOW_SCALE_Y 1.4f
#define WALLIFY_GLOW_ROTATION 1.605702912f

typedef struct {
    int texture_id, kind;
    float dx, dy, dw, dh;
    float sx, sy, sw, sh;
    float r, g, b, alpha;
    float radius, stroke;
    float clip_x, clip_y, clip_w, clip_h, clip_radius;
    float parameter;
} DrawCommand;
#endif
