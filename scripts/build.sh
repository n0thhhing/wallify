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
case "$MODE" in Debug) OPT=-Onone; NATIVE_OPT=-O0 ;; ReleaseFast|ReleaseSafe|ReleaseSmall|Release) OPT=-O; NATIVE_OPT=-O2 ;; *) echo "Unknown optimization: $MODE" >&2; exit 1 ;; esac
ARCHITECTURE="$(uname -m)"
VARIANT="$MODE"
[[ "$INSPECTOR" != true ]] || VARIANT="$VARIANT-Inspector"
BUILD_ROOT="build/variants/$VARIANT-$ARCHITECTURE"
mkdir -p "$BUILD_ROOT/bin" "$BUILD_ROOT/lib" "$BUILD_ROOT/resources/assets" "$BUILD_ROOT/objects"
BUILD_IDENTITY="$(python3 scripts/build-tools.py identity "$BUILD_ROOT" "$MODE" "$INSPECTOR" "$ARCHITECTURE")"
echo "==> $BUILD_IDENTITY"
TOOLCHAIN="$(xcrun --find swiftc):$(xcrun swiftc --version 2>&1):$(xcrun --show-sdk-path):$(xcrun --show-sdk-version):$(xcrun clang++ --version)"

build_if_needed() {
    local output="$1" signature
    shift
    local inputs=()
    while [[ "$1" != -- ]]; do inputs+=("$1"); shift; done
    shift
    signature="$({ printf '%s\n' "$TOOLCHAIN"; printf '%q ' "$@"; shasum -a 256 scripts/build.sh scripts/build-tools.py "${inputs[@]}"; } | shasum -a 256)"
    if [[ -f "$output" && -f "$output.sha256" && "$(<"$output.sha256")" == "$signature" ]]; then
        echo "  Up to date: $output"
        return
    fi
    echo "  Building: $output"
    # A failed command must never leave a previously valid cache stamp behind.
    rm -f "$output.sha256"
    "$@"
    printf '%s\n' "$signature" > "$output.sha256"
}

swift_output_map() {
    python3 - "$@" <<'PY'
import json, pathlib, sys
directory = pathlib.Path(sys.argv[1])
directory.mkdir(parents=True, exist_ok=True)
outputs = {"": {"swift-dependencies": str(directory / "build.swiftdeps")}}
for source in sys.argv[2:]:
    path = directory / source
    path.parent.mkdir(parents=True, exist_ok=True)
    outputs[source] = {"object": str(path.with_suffix(".o")),
                       "swift-dependencies": str(path.with_suffix(".swiftdeps"))}
path = directory / "outputs.json"
content = json.dumps(outputs, sort_keys=True)
if not path.exists() or path.read_text() != content:
    path.write_text(content)
print(path)
PY
}

COMMON=(-swift-version 5 -module-cache-path /tmp/wallify-swift-modules -target "$(uname -m)-apple-macosx12.0" -sdk "$(xcrun --show-sdk-path)")
TEST_COMMON=("${COMMON[@]}")
CXX_COMMON=(xcrun "$(xcrun --find clang++)" "$NATIVE_OPT" -mmacosx-version-min=12.0 -std=c++17 -fobjc-arc -fmodules -Wno-deprecated-declarations -isysroot "$(xcrun --show-sdk-path)")
HEADERS=()
while IFS= read -r header; do HEADERS+=("$header"); done < <(find src -name '*.h' -type f | sort)
SOURCES=()
while IFS= read -r source; do
    case "$source" in */metadata_fetcher.swift|*/native_bindings.swift|*/wallify.swift) ;; *) SOURCES+=("$source") ;; esac
done < <(find src -name '*.swift' -type f | sort)
HELPER_COMMAND=(xcrun swiftc "${COMMON[@]}" "$OPT" -emit-library -module-name MetadataFetcher -no-toolchain-stdlib-rpath -Xlinker -install_name -Xlinker @rpath/libmetadata_fetcher.dylib src/media/metadata_fetcher.swift -o "$BUILD_ROOT/lib/libmetadata_fetcher.dylib")
build_if_needed "$BUILD_ROOT/lib/libmetadata_fetcher.dylib" src/media/metadata_fetcher.swift -- "${HELPER_COMMAND[@]}"
build_if_needed "$BUILD_ROOT/objects/shaders.air" src/platform/gpu.h src/platform/shaders.metal -- xcrun -sdk macosx metal -fmodules-cache-path=/tmp/wallify-metal-modules -c -include src/platform/gpu.h src/platform/shaders.metal -o "$BUILD_ROOT/objects/shaders.air"
build_if_needed "$BUILD_ROOT/bin/default.metallib" "$BUILD_ROOT/objects/shaders.air" -- xcrun -sdk macosx metallib "$BUILD_ROOT/objects/shaders.air" -o "$BUILD_ROOT/bin/default.metallib"
for asset in assets/sprites/bin/*.bin; do
    build_if_needed "$BUILD_ROOT/resources/assets/$(basename "$asset")" "$asset" -- cp "$asset" "$BUILD_ROOT/resources/assets/"
done
OBJECTS=()
NATIVE_COMMANDS=()
IMGUI_HEADERS=()
if [[ "$INSPECTOR" == true ]]; then
    bash ./scripts/fetch-imgui.sh
    COMMON+=(-D DEBUG_INSPECTOR)
    while IFS= read -r header; do IMGUI_HEADERS+=("$header"); done < <(find build/vendor/imgui -name '*.h' -type f | sort)
fi
for source in build/vendor/imgui/{imgui,imgui_draw,imgui_tables,imgui_widgets}.cpp build/vendor/imgui/backends/{imgui_impl_osx,imgui_impl_metal}.mm src/ui/debug_imgui.mm; do
    object="$BUILD_ROOT/objects/$(basename "$source").o"
    command=("${CXX_COMMON[@]}" -Ibuild/vendor/imgui -Ibuild/vendor/imgui/backends -c "$source" -o "$object")
    NATIVE_COMMANDS+=(-- "${command[@]}")
    if [[ "$INSPECTOR" == true ]]; then
        inputs=("$source" "${IMGUI_HEADERS[@]}")
        if [[ "$source" == src/* ]]; then inputs+=("${HEADERS[@]}"); fi
        build_if_needed "$object" "${inputs[@]}" -- "${command[@]}"
        OBJECTS+=("$object")
    fi
done
if [[ "$INSPECTOR" == true ]]; then
    OBJECTS+=(-lc++ -framework MetalKit -framework GameController)
fi
# The checked-in ImGui snapshot is browsable too, but is not linked into the app.
for source in third_party/imgui/*.cpp third_party/imgui/backends/*.h; do
    [[ -f "$source" ]] || continue
    language=c++
    [[ "$source" != */backends/*.h ]] || language=objective-c++
    NATIVE_COMMANDS+=(-- "${CXX_COMMON[@]}" -Ithird_party/imgui -Ithird_party/imgui/backends -x "$language" -c "$source")
done
for header in "${HEADERS[@]}"; do
    # Matching .swift basenames otherwise make clangd infer Swift flags for .h.
    # Objective-C++ also covers settings_window.h's AppKit declarations.
    NATIVE_COMMANDS+=(-- "${CXX_COMMON[@]}" -x objective-c++ -c "$header")
done
APP_SOURCES=("${SOURCES[@]}" src/native_bindings.swift src/wallify.swift "$BUILD_ROOT/BuildIdentity.swift")
APP_MAP="$(swift_output_map "$BUILD_ROOT/objects/swift-$MODE-$INSPECTOR" "${APP_SOURCES[@]}")"
APP_INPUTS=("${APP_SOURCES[@]}" "${HEADERS[@]}" "$APP_MAP")
for object in ${OBJECTS[@]+"${OBJECTS[@]}"}; do [[ "$object" != *.o ]] || APP_INPUTS+=("$object"); done
APP_COMMAND=(xcrun swiftc "${COMMON[@]}" "$OPT" -incremental -enable-batch-mode -output-file-map "$APP_MAP" -import-objc-header src/platform/settings_bridge.h "${APP_SOURCES[@]}" ${OBJECTS[@]+"${OBJECTS[@]}"} -o "$BUILD_ROOT/bin/wallify")
# Editor metadata must exist even on cached builds and when tests are not run.
# Use the real command arrays so bridge imports and source membership cannot drift.
TEST_SOURCES=("${SOURCES[@]}" src/media/metadata_fetcher.swift tests/*.swift "$BUILD_ROOT/BuildIdentity.swift")
TEST_MAP="$(swift_output_map "$BUILD_ROOT/objects/tests-$MODE" "${TEST_SOURCES[@]}")"
TEST_COMMAND=(xcrun swiftc "${TEST_COMMON[@]}" "$OPT" -incremental -enable-batch-mode -output-file-map "$TEST_MAP" -import-objc-header src/platform/settings_bridge.h "${TEST_SOURCES[@]}" -o "$BUILD_ROOT/bin/settings-bridge-check")
python3 scripts/editor-commands.py "${APP_COMMAND[@]}" -- "${HELPER_COMMAND[@]}" -- "${TEST_COMMAND[@]}" "${NATIVE_COMMANDS[@]}"
build_if_needed "$BUILD_ROOT/bin/wallify" "${APP_INPUTS[@]}" -- "${APP_COMMAND[@]}"
if [[ "$TEST" == true ]]; then
    # Test callbacks deliberately replace the application's native bindings.
    build_if_needed "$BUILD_ROOT/bin/settings-bridge-check" "${TEST_SOURCES[@]}" "${HEADERS[@]}" "$TEST_MAP" -- "${TEST_COMMAND[@]}"
    /usr/bin/perl tests/helper-loader.pl "$BUILD_ROOT/lib/libmetadata_fetcher.dylib"
    "$BUILD_ROOT/bin/settings-bridge-check" --metallib "$PWD/$BUILD_ROOT/bin/default.metallib"
    "$BUILD_ROOT/bin/settings-bridge-check" --settings --metallib "$PWD/$BUILD_ROOT/bin/default.metallib"
fi
python3 scripts/build-tools.py select "$BUILD_ROOT"
echo "Swift build complete: $BUILD_IDENTITY ($BUILD_ROOT)."
