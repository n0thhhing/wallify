#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

zig build preview-cat
sips -s format png /tmp/wallify-poses.ppm --out /tmp/wallify-poses.png >/dev/null
open /tmp/wallify-poses.png
