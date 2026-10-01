#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
MODE=ReleaseFast
TEST=false
INSPECTOR=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test) TEST=true; shift ;;
        --debug-inspector) INSPECTOR=true; shift ;;
        -O|--optimize) MODE="$2"; shift 2 ;;
        *) echo "Unknown build option: $1" >&2; exit 1 ;;
    esac
done
case "$MODE" in Debug) OPT=-Onone ;; ReleaseFast|ReleaseSafe|ReleaseSmall|Release) OPT=-O ;; *) echo "Unknown optimization: $MODE" >&2; exit 1 ;; esac
mkdir -p build/bin build/lib build/resources/assets build/objects
COMMON=(-swift-version 5 -module-cache-path /tmp/wallify-swift-modules -target "$(uname -m)-apple-macosx12.0")
SOURCES=()
while IFS= read -r source; do
    case "$source" in */metadata_fetcher.swift|*/native_bindings.swift|*/wallify.swift) ;; *) SOURCES+=("$source") ;; esac
done < <(find src -name '*.swift' -type f | sort)
xcrun swiftc "${COMMON[@]}" "$OPT" -emit-library -module-name MetadataFetcher -no-toolchain-stdlib-rpath -Xlinker -install_name -Xlinker @rpath/libmetadata_fetcher.dylib src/media/metadata_fetcher.swift -o build/lib/libmetadata_fetcher.dylib
xcrun -sdk macosx metal -fmodules-cache-path=/tmp/wallify-metal-modules -c -include src/platform/gpu.h src/platform/shaders.metal -o build/objects/shaders.air
xcrun -sdk macosx metallib build/objects/shaders.air -o build/bin/default.metallib
cp src/assets/bin/*.bin build/resources/assets/
OBJECTS=()
if [[ "$INSPECTOR" == true ]]; then
    bash ./scripts/fetch-imgui.sh
    COMMON+=(-D DEBUG_INSPECTOR)
    for source in build/vendor/imgui/{imgui,imgui_draw,imgui_tables,imgui_widgets}.cpp build/vendor/imgui/backends/{imgui_impl_osx,imgui_impl_metal}.mm src/ui/debug_imgui.mm; do
        object="build/objects/$(basename "$source").o"
        xcrun clang++ -mmacosx-version-min=12.0 -std=c++17 -fobjc-arc -fmodules -Wno-deprecated-declarations -Ibuild/vendor/imgui -Ibuild/vendor/imgui/backends -c "$source" -o "$object"
        OBJECTS+=("$object")
    done
    OBJECTS+=(-lc++ -framework MetalKit -framework GameController)
fi
xcrun swiftc "${COMMON[@]}" "$OPT" -import-objc-header src/platform/settings_bridge.h "${SOURCES[@]}" src/native_bindings.swift src/wallify.swift ${OBJECTS[@]+"${OBJECTS[@]}"} -o build/bin/wallify
if [[ "$TEST" == true ]]; then
    # Test callbacks deliberately replace the application's native bindings.
    xcrun swiftc -swift-version 5 "$OPT" -module-cache-path /tmp/wallify-swift-modules -import-objc-header src/platform/settings_bridge.h "${SOURCES[@]}" src/media/metadata_fetcher.swift tests/*.swift -o build/bin/settings-bridge-check
    /usr/bin/perl tests/helper-loader.pl build/lib/libmetadata_fetcher.dylib
    build/bin/settings-bridge-check --metallib "$PWD/build/bin/default.metallib"
    build/bin/settings-bridge-check --settings --metallib "$PWD/build/bin/default.metallib"
fi
echo "Swift build complete ($MODE)."
