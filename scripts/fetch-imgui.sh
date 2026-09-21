#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$ROOT/.zig-cache/wallify-imgui"
REMOTE="https://github.com/ocornut/imgui.git"
COMMIT="4212de7d5b651895ccfe728f4eef9595e1d8d38a"

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to build the debug inspector." >&2
    exit 1
fi

mkdir -p "$(dirname -- "$CACHE_DIR")"

if [[ ! -d "$CACHE_DIR/.git" ]]; then
    rm -rf "$CACHE_DIR"
    git init -q "$CACHE_DIR"
    git -C "$CACHE_DIR" remote add origin "$REMOTE"
fi

CURRENT="$(git -C "$CACHE_DIR" rev-parse HEAD 2>/dev/null || true)"
if [[ "$CURRENT" != "$COMMIT" ]]; then
    echo "==> Fetching Dear ImGui (docking @ $COMMIT)..."
    git -C "$CACHE_DIR" fetch -q --depth 1 origin "$COMMIT"
    git -C "$CACHE_DIR" checkout -q --detach "$COMMIT"
fi

for required in \
    imgui.h \
    imgui.cpp \
    imgui_draw.cpp \
    imgui_tables.cpp \
    imgui_widgets.cpp \
    imconfig.h \
    imstb_rectpack.h \
    imstb_textedit.h \
    imstb_truetype.h \
    backends/imgui_impl_osx.h \
    backends/imgui_impl_osx.mm \
    backends/imgui_impl_metal.h \
    backends/imgui_impl_metal.mm
do
    if [[ ! -f "$CACHE_DIR/$required" ]]; then
        echo "Error: Dear ImGui cache is incomplete: $required" >&2
        exit 1
    fi
done

echo "  ✓ Dear ImGui ready at $CACHE_DIR"
