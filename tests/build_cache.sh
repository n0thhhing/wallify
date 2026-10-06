#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/wallify-build-cache.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH"/{scripts,src/media,src/platform,assets/sprites/bin,tests,tools,third_party/imgui/backends}
cp "$ROOT/scripts/build.sh" "$ROOT/scripts/editor-commands.py" "$SCRATCH/scripts/"
touch "$SCRATCH/src/media/metadata_fetcher.swift" "$SCRATCH/src/native_bindings.swift" "$SCRATCH/src/wallify.swift" "$SCRATCH/src/player.swift"
touch "$SCRATCH/src/platform/settings_bridge.h" "$SCRATCH/src/platform/gpu.h" "$SCRATCH/src/platform/shaders.metal"
touch "$SCRATCH/assets/sprites/bin/cat.bin" "$SCRATCH/tests/check.swift" "$SCRATCH/tests/helper-loader.pl"
touch "$SCRATCH/third_party/imgui/imgui.cpp" "$SCRATCH/third_party/imgui/backends/imgui_impl_metal.h"
cat > "$SCRATCH/tools/xcrun" <<'PY'
#!/usr/bin/env python3
import hashlib, os, pathlib, sys
args = sys.argv[1:]
if args[:2] == ['--find', 'clang++']:
    print(os.environ.get('FAKE_TOOLCHAIN', 'test-toolchain') + '/clang++')
    sys.exit(0)
if args[0] == '--find' or args[0].startswith('--show-sdk') or '--version' in args:
    print(os.environ.get('FAKE_TOOLCHAIN', 'test-toolchain'))
    sys.exit(0)
output = pathlib.Path(args[args.index('-o') + 1])
with open(os.environ['BUILD_LOG'], 'a') as log:
    log.write(str(output) + '\n')
output.parent.mkdir(parents=True, exist_ok=True)
if os.environ.get('FAIL_BUILD'):
    output.write_text('broken')
    sys.exit(1)
if output.name in ('wallify', 'settings-bridge-check'):
    output.write_text('#!/bin/sh\nexit 0\n')
    output.chmod(0o755)
else:
    inputs = b''.join(pathlib.Path(a).read_bytes() for a in args if pathlib.Path(a).is_file())
    output.write_text(hashlib.sha256(inputs).hexdigest())
PY
chmod +x "$SCRATCH/tools/xcrun"
export PATH="$SCRATCH/tools:$PATH" BUILD_LOG="$SCRATCH/commands.log"
cd "$SCRATCH"
build() { : > "$BUILD_LOG"; bash scripts/build.sh "$@" > /dev/null; }
expect() { diff -u <(printf '%s\n' "$@" | sed '/^$/d') "$BUILD_LOG"; }
build
expect build/lib/libmetadata_fetcher.dylib build/objects/shaders.air build/bin/default.metallib build/bin/wallify
cmp assets/sprites/bin/cat.bin build/resources/assets/cat.bin
python3 - <<'PY'
import json
from pathlib import Path
entries = {entry['file']: entry for entry in json.loads(Path('compile_commands.json').read_text())}
assert {file for file in entries if file.endswith('.swift')} == {str(path) for folder in ('src', 'tests') for path in Path(folder).rglob('*.swift')}
app = entries['src/player.swift']['arguments']
assert app[app.index('-import-objc-header') + 1] == 'src/platform/settings_bridge.h'
assert 'src/native_bindings.swift' in app and 'tests/check.swift' not in app
assert 'src/platform/settings_bridge.h' not in entries['src/media/metadata_fetcher.swift']['arguments']
test = entries['tests/check.swift']['arguments']
assert 'src/player.swift' in test and 'src/media/metadata_fetcher.swift' in test
assert 'src/native_bindings.swift' not in test and 'src/wallify.swift' not in test
native = entries['src/ui/debug_imgui.mm']['arguments']
assert native[0].endswith('/clang++') and '-std=c++17' in native and '-fobjc-arc' in native
assert '-isysroot' in native and '-Ibuild/vendor/imgui' in native
vendor = entries['third_party/imgui/imgui.cpp']['arguments']
assert '-Ithird_party/imgui' in vendor and '-Ibuild/vendor/imgui' not in vendor
metal = entries['third_party/imgui/backends/imgui_impl_metal.h']['arguments']
assert metal[metal.index('-x') + 1] == 'objective-c++'
for header in Path('src').rglob('*.h'):
    native = entries[str(header)]['arguments']
    assert native[0].endswith('/clang++') and '-Onone' not in native
    assert native[native.index('-x') + 1] == 'objective-c++'
PY
rm compile_commands.json
build; expect
test -f compile_commands.json
printf 'sprite change' >> assets/sprites/bin/cat.bin
build; expect
cmp assets/sprites/bin/cat.bin build/resources/assets/cat.bin
echo '// change' >> src/wallify.swift
build; expect build/bin/wallify
echo '// change' >> src/media/metadata_fetcher.swift
build; expect build/lib/libmetadata_fetcher.dylib
echo '// change' >> src/platform/gpu.h
build; expect build/objects/shaders.air build/bin/default.metallib build/bin/wallify
build --test; expect build/bin/settings-bridge-check
build --test; expect
echo '// change' >> tests/check.swift
build --test; expect build/bin/settings-bridge-check
build -O Debug; expect build/lib/libmetadata_fetcher.dylib build/bin/wallify
rm build/bin/wallify
build -O Debug; expect build/bin/wallify
echo '// new' > src/new.swift
build -O Debug; expect build/bin/wallify
rm src/new.swift
build -O Debug; expect build/bin/wallify
mkdir -p build/vendor/imgui/backends
touch build/vendor/imgui/{imgui,imgui_draw,imgui_tables,imgui_widgets}.cpp build/vendor/imgui/imgui.h
touch build/vendor/imgui/backends/{imgui_impl_osx,imgui_impl_metal}.mm
mkdir -p src/ui
touch src/ui/debug_imgui.mm
printf '#!/bin/sh\nexit 0\n' > scripts/fetch-imgui.sh
build -O Debug --debug-inspector
expect build/objects/imgui.cpp.o build/objects/imgui_draw.cpp.o build/objects/imgui_tables.cpp.o build/objects/imgui_widgets.cpp.o build/objects/imgui_impl_osx.mm.o build/objects/imgui_impl_metal.mm.o build/objects/debug_imgui.mm.o build/bin/wallify
build -O Debug --debug-inspector; expect
python3 - <<'PY'
import json
from pathlib import Path
entries = {entry['file']: entry for entry in json.loads(Path('compile_commands.json').read_text())}
assert 'DEBUG_INSPECTOR' in entries['src/player.swift']['arguments']
assert 'DEBUG_INSPECTOR' not in entries['tests/check.swift']['arguments']
PY
echo '// change' >> src/platform/gpu.h
build -O Debug --debug-inspector
expect build/objects/shaders.air build/bin/default.metallib build/objects/debug_imgui.mm.o build/bin/wallify
build -O Debug; expect build/bin/wallify
echo '// change' >> src/wallify.swift
if FAIL_BUILD=1 build -O Debug; then echo 'Failed build unexpectedly succeeded'; exit 1; fi
[[ ! -f build/bin/wallify.sha256 ]]
build -O Debug; expect build/bin/wallify
FAKE_TOOLCHAIN=new build -O Debug
expect build/lib/libmetadata_fetcher.dylib build/objects/shaders.air build/bin/default.metallib build/bin/wallify
echo 'Build cache checks passed'
