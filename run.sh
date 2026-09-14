#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

echo "Stopping existing Wallify instances..."
pkill -x Wallify || true

echo "Building Wallify..."
zig build

echo "Packaging App..."
if [[ -x "scripts/package-app.sh" ]]; then
    bash scripts/package-app.sh
fi

echo "Launching Wallify..."
if [[ "$OSTYPE" == "darwin"* ]] && [[ -x "./zig-out/Wallify.app/Contents/MacOS/Wallify" ]]; then
    exec ./zig-out/Wallify.app/Contents/MacOS/Wallify "$@"
else
    exec ./zig-out/bin/wallify "$@"
fi
