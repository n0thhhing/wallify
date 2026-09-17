#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

AGENT="${WALLIFY_LAUNCH_AGENT:-com.levi.spotify-panel}"

echo -e "${BOLD}${CYAN}==>${RESET} ${BOLD}Deep Cleaning Wallify...${RESET}"

# 1. Stop background services and processes
echo -e "  ${CYAN}•${RESET} Stopping LaunchAgent and processes..."
launchctl bootout "gui/$(id -u)/${AGENT}" 2>/dev/null || true
pkill -x "Wallify" 2>/dev/null || true
pkill -f "metadata_fetcher.dylib" 2>/dev/null || true

# 2. Wipe temporary artwork files
echo -e "  ${CYAN}•${RESET} Wiping temporary artwork files (/tmp/)..."
rm -f /tmp/art.raw /tmp/art.bmp /tmp/art-next.bmp /tmp/mrc_artwork /tmp/mrc_artwork_tmp /tmp/wallify-poses.ppm /tmp/wallify-poses.png 2>/dev/null || true

# 3. Nuke Zig caches and build output
echo -e "  ${CYAN}•${RESET} Nuking zig-cache and build directories..."
rm -rf zig-cache .zig-cache zig-out 2>/dev/null || true

echo -e "  ${GREEN}✓${RESET} Clean slate achieved. Run 'zig build' to recompile."
