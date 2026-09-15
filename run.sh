#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Build successfully before stopping the running widget.
zig build -Doptimize=ReleaseFast
pkill -x Wallify 2>/dev/null || true
bash scripts/package-app.sh
exec open "$PWD/zig-out/Wallify.app"
