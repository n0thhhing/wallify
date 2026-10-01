#pragma once
#include <stdbool.h>
#include <stddef.h>

typedef struct {
    double elapsed, sampled_at, rate, correction;
} WallifyPlaybackClock;

typedef struct {
    int pending; // -1: no intent, 0: pause, 1: play
    double deadline, confirmed_since; // -1: not yet confirmed
} WallifyPlaybackIntent;

typedef struct { size_t offset, count; } WallifyMediaSpan;
typedef struct {
    WallifyMediaSpan title, artist, artwork;
    double rate, elapsed, duration;
    bool has_artwork;
} WallifyMediaPayload;
