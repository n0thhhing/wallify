#!/usr/bin/env bash
set -euo pipefail

# Navigate to project root
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

APP_NAME="Wallify"
BUNDLE_ID="com.wallify.widget"
APP_DIR="$PWD/zig-out/${APP_NAME}.app"
ENTITLEMENTS="$PWD/scripts/Wallify.entitlements"

DO_BUILD=false
DO_INSTALL=false
DO_DMG=false
DO_RUN=false
OPTIMIZE="${OPTIMIZE:-ReleaseFast}"

show_help() {
    echo -e "${BOLD}${APP_NAME} Packaging Utility${RESET}"
    echo ""
    echo "Usage: ./scripts/package-app.sh [options]"
    echo ""
    echo "Options:"
    echo "  -b, --build             Force re-compile with 'zig build' first"
    echo "  -O, --optimize <mode>   Optimization level: ReleaseFast (default), Debug, ReleaseSafe, ReleaseSmall"
    echo "  -i, --install           Install application to /Applications/${APP_NAME}.app"
    echo "  -d, --dmg               Create a redistributable DMG installer at zig-out/${APP_NAME}.dmg"
    echo "  -r, --run               Relaunch the app immediately after packaging"
    echo "  -h, --help              Show this help message"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--build) DO_BUILD=true; shift ;;
        -O|--optimize) OPTIMIZE="$2"; DO_BUILD=true; shift 2 ;;
        -i|--install) DO_INSTALL=true; shift ;;
        -d|--dmg) DO_DMG=true; shift ;;
        -r|--run) DO_RUN=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${RESET}"; show_help; exit 1 ;;
    esac
done

echo -e "${BOLD}${BLUE}==>${RESET} ${BOLD}Packaging ${APP_NAME}.app...${RESET}"

# 1. Build project if requested or if binaries are missing
if [[ "$DO_BUILD" == true ]] || [[ ! -f "zig-out/bin/wallify" ]] || [[ ! -f "zig-out/lib/libmetadata_fetcher.dylib" ]] || [[ ! -f "zig-out/bin/default.metallib" ]]; then
    echo -e "  ${CYAN}•${RESET} Compiling binaries via zig build (-Doptimize=${OPTIMIZE})..."
    # Ensure macOS SDK path is discovered properly
    if ! xcrun --show-sdk-path >/dev/null 2>&1; then
        if [[ -d "/Library/Developer/CommandLineTools" ]]; then
            export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
        fi
    fi
    zig build -Doptimize="${OPTIMIZE}"
fi

# Sanity check required binaries
for bin in "zig-out/bin/wallify" "zig-out/lib/libmetadata_fetcher.dylib" "zig-out/bin/default.metallib"; do
    if [[ ! -f "$bin" ]]; then
        echo -e "${RED}Error: Required build artifact missing: $bin${RESET}" >&2
        exit 1
    fi
done

# 2. Clean & create app bundle layout
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" \
         "$APP_DIR/Contents/Frameworks" \
         "$APP_DIR/Contents/Resources/assets" \
         "$APP_DIR/Contents/Resources/zig-out/lib"

# 3. Copy binaries & libraries
cp zig-out/bin/wallify "$APP_DIR/Contents/MacOS/Wallify"
chmod +x "$APP_DIR/Contents/MacOS/Wallify"

# Place dynamic libraries in Frameworks and legacy Resources path
cp zig-out/lib/libmetadata_fetcher.dylib "$APP_DIR/Contents/Frameworks/"
cp zig-out/lib/libmetadata_fetcher.dylib "$APP_DIR/Contents/Resources/zig-out/lib/"

# 4. Copy Metal shaders & assets
cp zig-out/bin/default.metallib "$APP_DIR/Contents/Resources/default.metallib"
if [[ -f assets/spotify_icon.png ]]; then
    cp assets/spotify_icon.png "$APP_DIR/Contents/Resources/assets/"
fi
if [[ -d assets/cat ]]; then
    cp -R assets/cat "$APP_DIR/Contents/Resources/assets/"
fi
if [[ -f widget-settings.conf ]]; then
    cp widget-settings.conf "$APP_DIR/Contents/Resources/"
fi

# 5. Ensure AppIcon.icns exists
if [[ -f assets/AppIcon.icns ]]; then
    cp assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# 6. Generate comprehensive Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Wallify</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Wallify uses Apple Events to display track metadata and control music playback.</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLIST

# 7. Code signing with entitlements and hardened runtime options
echo -e "  ${CYAN}•${RESET} Signing binaries & bundle..."
SIGN_ARGS=(--force --sign -)
if [[ -f "$ENTITLEMENTS" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
fi

# Sign frameworks and executable
codesign "${SIGN_ARGS[@]}" "$APP_DIR/Contents/Frameworks/libmetadata_fetcher.dylib"
codesign "${SIGN_ARGS[@]}" "$APP_DIR/Contents/MacOS/Wallify"
# Sign top-level bundle
codesign --force --deep --sign - "${SIGN_ARGS[@]}" "$APP_DIR"

# Verify signature
codesign --verify --deep --strict "$APP_DIR"
echo -e "  ${GREEN}✓${RESET} Bundle signed and verified successfully."

# 8. Optional: Install to /Applications
if [[ "$DO_INSTALL" == true ]]; then
    echo -e "  ${CYAN}•${RESET} Installing to /Applications/${APP_NAME}.app..."
    pkill -x "${APP_NAME}" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP_DIR" "/Applications/${APP_NAME}.app"
    echo -e "  ${GREEN}✓${RESET} Installed to /Applications/${APP_NAME}.app"
fi

# 9. Optional: Generate DMG disk image
if [[ "$DO_DMG" == true ]]; then
    DMG_PATH="zig-out/${APP_NAME}.dmg"
    DMG_TMP="/tmp/${APP_NAME}-dmg"
    echo -e "  ${CYAN}•${RESET} Creating disk image: ${DMG_PATH}..."
    rm -rf "$DMG_TMP" "$DMG_PATH"
    mkdir -p "$DMG_TMP"
    cp -R "$APP_DIR" "$DMG_TMP/"
    ln -s /Applications "$DMG_TMP/Applications"
    
    hdiutil create -volname "${APP_NAME}" \
                   -srcfolder "$DMG_TMP" \
                   -ov \
                   -format UDZO \
                   "$DMG_PATH" >/dev/null
    rm -rf "$DMG_TMP"
    echo -e "  ${GREEN}✓${RESET} Disk image generated at ${DMG_PATH}"
fi

# 10. Optional: Relaunch app
if [[ "$DO_RUN" == true ]]; then
    echo -e "  ${CYAN}•${RESET} Relaunching ${APP_NAME}..."
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 0.2
    open "$APP_DIR"
    echo -e "  ${GREEN}✓${RESET} ${APP_NAME} running."
fi

APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo -e "${GREEN}${BOLD}Done!${RESET} ${APP_NAME}.app created at ${CYAN}${APP_DIR}${RESET} (${APP_SIZE})"
