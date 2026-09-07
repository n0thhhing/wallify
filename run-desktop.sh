#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if command -v kitten >/dev/null 2>&1; then
    panel_kitten="$(command -v kitten)"
else
    panel_kitten=/Applications/kitty.app/Contents/MacOS/kitten
fi

# Keep runtime builds separate from a stale project cache left by interrupted
# panel runs; Kitty can then relaunch the current binary reliably.
zig build -Doptimize=ReleaseFast --cache-dir /tmp/wallify-runtime-cache --global-cache-dir /tmp/wallify-runtime-global-cache
if [[ ! -f preview_frame || preview.swift -nt preview_frame ]]; then
    swiftc -O preview.swift -o preview_frame
fi
export WALLIFY_DESKTOP=1
panel_height="${WALLIFY_HEIGHT:-205}"
panel_width="${WALLIFY_WIDTH:-708}"
grid_x=0
grid_y=0
if [[ -f widget-settings.conf ]] && grep -q '^widget_mode=0$' widget-settings.conf; then
    # The mini tile sits in the same visual row as the desktop widgets.
    panel_height="${WALLIFY_COMPACT_HEIGHT:-232}"
    panel_width="${WALLIFY_COMPACT_WIDTH:-174}"
fi
if [[ -f widget-settings.conf ]]; then
    saved_x="$(sed -n 's/^widget_grid_x=\([0-9][0-9]*\)$/\1/p' widget-settings.conf | head -n 1)"
    saved_y="$(sed -n 's/^widget_grid_y=\([0-9][0-9]*\)$/\1/p' widget-settings.conf | head -n 1)"
    saved_left="$(sed -E -n 's/^widget_margin_left=(-?[0-9]+)$/\1/p' widget-settings.conf | head -n 1)"
    saved_top="$(sed -E -n 's/^widget_margin_top=(-?[0-9]+)$/\1/p' widget-settings.conf | head -n 1)"
    [[ "$saved_x" =~ ^[0-9]+$ ]] && grid_x="$saved_x"
    [[ "$saved_y" =~ ^[0-9]+$ ]] && grid_y="$saved_y"
    [[ "$saved_left" =~ ^-?[0-9]+$ ]] && panel_margin_left="$saved_left"
    [[ "$saved_top" =~ ^-?[0-9]+$ ]] && panel_margin_top="$saved_top"
fi
panel_margin_left="${panel_margin_left:-$((14 + grid_x * 180))}"
panel_margin_top="${panel_margin_top:-$((12 + grid_y * 180))}"

killall preview_frame 2>/dev/null || true
killall spotify-player 2>/dev/null || true

rm -f /tmp/wallify-kitty.sock
if "$panel_kitten" panel \
    --edge=none \
    --layer=bottom \
    --focus-policy=on-demand \
    --listen-on=unix:/tmp/wallify-kitty.sock \
    --columns="${panel_width}px" --lines="${panel_height}px" \
    --margin-left="$panel_margin_left" --margin-top="$panel_margin_top" \
    --config="$PWD/widget-kitty.conf" \
    ./zig-out/bin/spotify-player; then
    panel_status=0
else
    panel_status=$?
fi

exit "$panel_status"
