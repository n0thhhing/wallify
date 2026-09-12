#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
zig build preview-cat
sips -s format png /tmp/wallify-poses.ppm --out /tmp/wallify-poses.png >/dev/null
open /tmp/wallify-poses.png
