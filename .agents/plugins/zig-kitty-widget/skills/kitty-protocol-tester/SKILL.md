---
name: kitty-protocol-tester
description: Guide and procedures for testing Kitty graphics protocol transmissions, OSC 66 text sizing, SGR mouse coordinate hit-testing, and cell aspect ratio calculations.
---

# Kitty Protocol Tester Skill

Use this skill when developing, debugging, or verifying terminal protocol features in Kitty for `wallify`.

---

## 1. Verifying Kitty Graphics Protocol

When inspecting or debugging Kitty graphics output:

1. **Verify Header Parameters:**
   - Format: `\x1b_Ga=T,f=32,s=<width>,v=<height>,i=<id>,p=<placement_id>,m=<more>;<base64>\x1b\`
   - Check that `f=32` is supplied for raw 32-bit RGBA buffers or `f=100` for PNG image data.
   - Ensure transmission chunks are strictly $\le 4096$ base64 characters with `m=1` on intermediate chunks and `m=0` on the final chunk.

2. **Verify Placement & Cleanup:**
   - Use `a=d,d=i,i=<id>` or `a=d,d=a` to cleanly delete images when switching tracks or resizing the widget.

---

## 2. Testing Cell Aspect Ratio & Font Dimensions

Terminal cell aspect ratio varies based on font family and line-height.
- Query pixel dimensions using `CSI 14 t` (window pixel size) or `CSI 16 t` (cell pixel size).
- Calculate rows needed for album art:
  $$\text{rows} = \text{round}\left(\text{cols} \times \text{cell\_aspect}\right)$$
- If aspect ratio query fails, fallback safely to `0.5` (a standard 2:1 height:width ratio).

---

## 3. Testing SGR 1006 Mouse Tracking

- Enable sequence: `\x1b[?1000h\x1b[?1002h\x1b[?1006h`
- Parse response: `\x1b[<BTN;COL;ROW(M|m)`
  - `BTN`: `0` for Left Button, `1` for Middle, `2` for Right, `32` for Drag/Motion.
  - `M`: Button down / Drag.
  - `m`: Button up.
  - `COL`, `ROW`: 1-based cell coordinates.
- Hitbox validation:
  - Check if `(col, row)` falls inside button bounding boxes (Play/Pause, Previous, Next).
  - Check if `row == bar_row` and `col` is within `[bar_x, bar_x + bar_w]` to trigger a timeline seek.
