# Rendering performance

Measured on the development Mac, October 1, 2026, using ReleaseFast.
Run `./scripts/build.sh -O ReleaseFast --test`, then:

```sh
build/bin/settings-bridge-check --benchmark --metallib "$PWD/build/bin/default.metallib"
```

The benchmark warms the text/static caches and reports the median of five
2,000-frame batches. Values below are medians of three fresh processes.
It measures CPU frame preparation without pumping GPU presentation; texture
bytes are Metal allocations, and scratch bytes are the text raster buffer.
These are not whole-process RSS, CPU utilization, or GPU timing measurements.

| Change | Frame preparation (µs) | Texture bytes | Text scratch bytes |
| --- | ---: | ---: | ---: |
| Baseline | 1.735 | 4,931,712 | 786,432 |
| Grow text scratch only as needed | 1.752 | 4,931,712 | 98,940 |
| Load pet atlases only when visible | 1.745 | 1,654,912 | 98,940 |
| Trial: reuse Canvas command arrays | 1.719 | 1,654,912 | 98,940 |

Kept the two memory improvements. CPU differences were within run-to-run
variation (the Canvas trial ranged from 1.661 to 1.770 µs), so the Canvas
change was discarded. Pet atlases remain cached after first use, bounded to
three pets; startup skips their decoding/upload until needed. Text scratch
retains the largest rendered label, bounded by the existing 2048×96 limit.
Tests cover rasterization, all three atlases, and repeated pet loading without
replacement. Animation rates and rendering quality are unchanged.

## Playback CPU improvement

Replacing Foundation's general-purpose timestamp formatting with integer
conversion reduced frame preparation from 1.719 µs (1.756, 1.696, 1.719)
to 0.771 µs (0.799, 0.771, 0.765), a 55% reduction. These measurements use
the same benchmark and ReleaseFast build as above; memory stayed unchanged.
This measures frame preparation, not whole-app CPU utilization. No update
rate or animation quality was reduced. Tests compare all 3,600 seconds of
an hour against the previous formatter and check negative/nonfinite values.
