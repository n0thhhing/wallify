#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
app="$PWD/zig-out/Wallify.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/assets" "$app/Contents/Resources/zig-out/lib"
cp zig-out/bin/wallify "$app/Contents/MacOS/Wallify"
cp zig-out/lib/libmetadata_fetcher.dylib "$app/Contents/Resources/zig-out/lib/"
cp assets/spotify_icon.png "$app/Contents/Resources/assets/"
cp zig-out/bin/default.metallib "$app/Contents/Resources/default.metallib"

if [[ -f widget-settings.conf ]]; then cp widget-settings.conf "$app/Contents/Resources/"; fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Wallify</string>
<key>CFBundleIdentifier</key><string>com.wallify.widget</string>
<key>CFBundleName</key><string>Wallify</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Wallify uses automation to display and control your music.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
