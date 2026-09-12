#!/usr/bin/env bash
set -euo pipefail
launchctl kickstart -k "gui/$(id -u)/${WALLIFY_LAUNCH_AGENT:-com.levi.spotify-panel}"
