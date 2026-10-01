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

## Window movement

Dragging now moves the native panel immediately on the main thread, without
waiting for the animation worker or requesting a Metal redraw for each
position change. macOS composites the existing surface at its new position.
Snap animation keeps its 60 Hz motion but does not redraw unchanged contents.
Playback, hover changes, and visual effects still redraw independently.
Regression checks verify that a pure drag produces a move and no redraw,
and that position-only updates and snap steps move without drawing.
This removes redundant submissions; whole-app CPU/GPU savings during live
dragging have not been measured.

## Live inspector readings

The inspector's Renderer and Performance pages show app CPU percentage,
completed widget redraws per second, and GPU time per completed widget frame.
Samples refresh at most once per second when stats are requested; no new
background timer is installed. CPU uses process user/system time, with 100%
representing one CPU core. It includes inspector overhead but excludes the
separate media helper and WindowServer. GPU/redraw values return to zero when
no widget frames complete in the sampling interval. The first sample establishes
the baseline. These readings work without WALLIFY_PROFILE; that flag still
enables detailed lifetime logs and upload counters.

Snap previews now ignore unchanged geometry/radius and repeated hides.
Unchanged previews also avoid the player-window query and window ordering.
Hiding clears the visible state so showing the same target again still works.

## SIMD layout interpolation

Layout mode endpoints are packed once into SIMD16<Double>; resizing
interpolates the 16 fields without allocating or dispatching writable key paths.
All 25 mode pairs are checked at intermediate, endpoint, and clamped mixes,
with invalid inputs still rejected.

Run `--benchmark-math` instead of `--benchmark` to measure layout and artwork
math. It consumes every layout field and checksums outputs. Alternating three
fresh scalar/SIMD processes gave layout medians of 0.404/0.005 µs (about 80×
faster); both produced checksum 181714614. The unchanged artwork-color control
was 20.512/20.364 µs. This improves layout calculations during resizing, not
whole-app CPU usage by 80×; steady frames already cache layout geometry.

A SIMD3<Double> RGB accumulation trial took 51.331 µs versus the original
20.462 µs for 180×180 artwork. It was discarded. Merely spelling an operation
as SIMD does not guarantee faster generated code.

### Snap distance SIMD trial

`--benchmark-snap` measures target selection with 64 candidates and varied
pointer positions. Pairing targets with SIMD2<Double> gave median 0.574 µs
versus scalar 0.591 µs. Scalar runs ranged from 0.577 to 0.632 µs, so the 3%
difference did not exceed normal variation. Both checksums were 29624600;
tie-breaking checks passed. Discarded the SIMD implementation and retained
the benchmark and equal-distance regression check.
