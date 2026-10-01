#pragma once
#include <stdbool.h>

typedef struct {
    double elapsed, sampled_at, rate, correction;
} WallifyPlaybackClock;

typedef struct {
    int pending; // -1: no intent, 0: pause, 1: play
    double deadline, confirmed_since; // -1: not yet confirmed
} WallifyPlaybackIntent;
