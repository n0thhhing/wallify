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
TOOLCHAIN="$(xcrun --find swiftc):$(xcrun swiftc --version 2>&1):$(xcrun --show-sdk-path):$(xcrun --show-sdk-version):$(xcrun clang++ --version)"

build_if_needed() {
    local output="$1" signature
    shift
    local inputs=()
    while [[ "$1" != -- ]]; do inputs+=("$1"); shift; done
    shift
    signature="$({ printf '%s\n' "$TOOLCHAIN"; printf '%q ' "$@"; shasum -a 256 scripts/build.sh "${inputs[@]}"; } | shasum -a 256)"
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

COMMON=(-swift-version 5 -module-cache-path /tmp/wallify-swift-modules -target "$(uname -m)-apple-macosx12.0")
HEADERS=()
while IFS= read -r header; do HEADERS+=("$header"); done < <(find src -name '*.h' -type f | sort)
SOURCES=()
while IFS= read -r source; do
    case "$source" in */metadata_fetcher.swift|*/native_bindings.swift|*/wallify.swift) ;; *) SOURCES+=("$source") ;; esac
done < <(find src -name '*.swift' -type f | sort)
build_if_needed build/lib/libmetadata_fetcher.dylib src/media/metadata_fetcher.swift -- xcrun swiftc "${COMMON[@]}" "$OPT" -emit-library -module-name MetadataFetcher -no-toolchain-stdlib-rpath -Xlinker -install_name -Xlinker @rpath/libmetadata_fetcher.dylib src/media/metadata_fetcher.swift -o build/lib/libmetadata_fetcher.dylib
build_if_needed build/objects/shaders.air src/platform/gpu.h src/platform/shaders.metal -- xcrun -sdk macosx metal -fmodules-cache-path=/tmp/wallify-metal-modules -c -include src/platform/gpu.h src/platform/shaders.metal -o build/objects/shaders.air
build_if_needed build/bin/default.metallib build/objects/shaders.air -- xcrun -sdk macosx metallib build/objects/shaders.air -o build/bin/default.metallib
for asset in src/assets/bin/*.bin; do
    build_if_needed "build/resources/assets/$(basename "$asset")" "$asset" -- cp "$asset" build/resources/assets/
done
OBJECTS=()
if [[ "$INSPECTOR" == true ]]; then
    bash ./scripts/fetch-imgui.sh
    COMMON+=(-D DEBUG_INSPECTOR)
    IMGUI_HEADERS=()
    while IFS= read -r header; do IMGUI_HEADERS+=("$header"); done < <(find build/vendor/imgui -name '*.h' -type f | sort)
    for source in build/vendor/imgui/{imgui,imgui_draw,imgui_tables,imgui_widgets}.cpp build/vendor/imgui/backends/{imgui_impl_osx,imgui_impl_metal}.mm src/ui/debug_imgui.mm; do
        object="build/objects/$(basename "$source").o"
        inputs=("$source" "${IMGUI_HEADERS[@]}")
        if [[ "$source" == src/* ]]; then inputs+=("${HEADERS[@]}"); fi
        build_if_needed "$object" "${inputs[@]}" -- xcrun clang++ -mmacosx-version-min=12.0 -std=c++17 -fobjc-arc -fmodules -Wno-deprecated-declarations -Ibuild/vendor/imgui -Ibuild/vendor/imgui/backends -c "$source" -o "$object"
        OBJECTS+=("$object")
    done
    OBJECTS+=(-lc++ -framework MetalKit -framework GameController)
fi
APP_SOURCES=("${SOURCES[@]}" src/native_bindings.swift src/wallify.swift)
APP_MAP="$(swift_output_map "build/objects/swift-$MODE-$INSPECTOR" "${APP_SOURCES[@]}")"
APP_INPUTS=("${APP_SOURCES[@]}" "${HEADERS[@]}" "$APP_MAP")
for object in ${OBJECTS[@]+"${OBJECTS[@]}"}; do [[ "$object" != *.o ]] || APP_INPUTS+=("$object"); done
build_if_needed build/bin/wallify "${APP_INPUTS[@]}" -- xcrun swiftc "${COMMON[@]}" "$OPT" -incremental -enable-batch-mode -output-file-map "$APP_MAP" -import-objc-header src/platform/settings_bridge.h "${APP_SOURCES[@]}" ${OBJECTS[@]+"${OBJECTS[@]}"} -o build/bin/wallify
if [[ "$TEST" == true ]]; then
    # Test callbacks deliberately replace the application's native bindings.
    TEST_SOURCES=("${SOURCES[@]}" src/media/metadata_fetcher.swift tests/*.swift)
    TEST_MAP="$(swift_output_map "build/objects/tests-$MODE" "${TEST_SOURCES[@]}")"
    build_if_needed build/bin/settings-bridge-check "${TEST_SOURCES[@]}" "${HEADERS[@]}" "$TEST_MAP" -- xcrun swiftc -swift-version 5 "$OPT" -module-cache-path /tmp/wallify-swift-modules -incremental -enable-batch-mode -output-file-map "$TEST_MAP" -import-objc-header src/platform/settings_bridge.h "${TEST_SOURCES[@]}" -o build/bin/settings-bridge-check
    /usr/bin/perl tests/helper-loader.pl build/lib/libmetadata_fetcher.dylib
    build/bin/settings-bridge-check --metallib "$PWD/build/bin/default.metallib"
    build/bin/settings-bridge-check --settings --metallib "$PWD/build/bin/default.metallib"
fi
echo "Swift build complete ($MODE)."
