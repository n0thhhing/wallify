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
APP_DIR="$PWD/build/${APP_NAME}.app"
FINAL_APP="$APP_DIR"
STAGING_DIR=""
trap '[[ -z "$STAGING_DIR" ]] || rm -rf "$STAGING_DIR"' EXIT
ENTITLEMENTS="$PWD/scripts/Wallify.entitlements"

DO_BUILD=false
DO_INSTALL=false
DO_DMG=false
DO_RUN=false
DO_KICKSTART=false
OPTIMIZE="${OPTIMIZE:-ReleaseFast}"

show_help() {
    echo -e "${BOLD}${APP_NAME} Packaging Utility${RESET}"
    echo ""
    echo "Usage: ./scripts/package-app.sh [options]"
    echo ""
    echo "Options:"
    echo "  -b, --build             Force re-compile with './scripts/build.sh' first"
    echo "  -O, --optimize <mode>   Optimization level: ReleaseFast (default), Debug, ReleaseSafe, ReleaseSmall"
    echo "  -i, --install           Install application to /Applications/${APP_NAME}.app"
    echo "  -d, --dmg               Create a redistributable DMG installer at build/${APP_NAME}.dmg"
    echo "  -r, --run               Relaunch the app immediately after packaging via 'open'"
    echo "  -k, --kickstart         Relaunch the app via launchctl (used for background widget mode)"
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
        -k|--kickstart) DO_KICKSTART=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${RESET}"; show_help; exit 1 ;;
    esac
done

echo -e "${BOLD}${BLUE}==>${RESET} ${BOLD}Packaging ${APP_NAME}.app...${RESET}"

# 1. Build project if requested or if binaries are missing
NEEDS_BUILD="$DO_BUILD"
for required in build/current/build-info.json build/bin/wallify build/bin/wallify.sha256 \
                build/lib/libmetadata_fetcher.dylib build/lib/libmetadata_fetcher.dylib.sha256 \
                build/bin/default.metallib build/bin/default.metallib.sha256; do
    [[ -f "$required" ]] || NEEDS_BUILD=true
done
if [[ "$NEEDS_BUILD" == true ]]; then
    echo -e "  ${CYAN}•${RESET} Compiling binaries via Swift (-O ${OPTIMIZE})..."
    # Ensure macOS SDK path is discovered properly
    if ! xcrun --show-sdk-path >/dev/null 2>&1; then
        if [[ -d "/Library/Developer/CommandLineTools" ]]; then
            export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
        fi
    fi
    BUILD_ARGS=(-O "${OPTIMIZE}")
    if [[ "${OPTIMIZE}" == "Debug" ]]; then
        BUILD_ARGS+=(--debug-inspector)
    fi
    ./scripts/build.sh "${BUILD_ARGS[@]}"
fi

# Pin one successful configuration so another build cannot change our inputs
# halfway through copying the app.
BUILD_ROOT="$(cd build/current && pwd)"
python3 - "$BUILD_ROOT/build-info.json" <<'PY'
import json, sys
print("  Build: " + json.load(open(sys.argv[1]))["label"])
PY

# Sanity check required binaries
for bin in "$BUILD_ROOT/bin/wallify" "$BUILD_ROOT/lib/libmetadata_fetcher.dylib" "$BUILD_ROOT/bin/default.metallib"; do
    if [[ ! -f "$bin" ]]; then
        echo -e "${RED}Error: Required build artifact missing: $bin${RESET}" >&2
        exit 1
    fi
done

PACKAGE_SIGNATURE="$(python3 scripts/build-tools.py package-signature "$BUILD_ROOT")"
if python3 scripts/build-tools.py cached "$FINAL_APP" "$PACKAGE_SIGNATURE"; then
    echo "  Up to date: $FINAL_APP (copying and signing skipped)"
else
    # Stage beside the destination so publication can use an atomic filesystem swap.
    STAGING_DIR="$(mktemp -d "$PWD/build/.package.XXXXXX")"
    APP_DIR="$STAGING_DIR/$APP_NAME.app"
    mkdir -p "$APP_DIR/Contents/MacOS" \
             "$APP_DIR/Contents/Frameworks" \
             "$APP_DIR/Contents/Resources/assets"

    # 3. Copy binaries & libraries
    cp "$BUILD_ROOT/bin/wallify" "$APP_DIR/Contents/MacOS/Wallify"
    chmod +x "$APP_DIR/Contents/MacOS/Wallify"

    # Place dynamic libraries in Frameworks
    cp "$BUILD_ROOT/lib/libmetadata_fetcher.dylib" "$APP_DIR/Contents/Frameworks/"

    # 4. Copy Metal shaders & assets
    cp "$BUILD_ROOT/bin/default.metallib" "$APP_DIR/Contents/Resources/default.metallib"
    cp "$BUILD_ROOT/build-info.json" "$APP_DIR/Contents/Resources/build-info.json"
    cp assets/sprites/bin/*.bin "$APP_DIR/Contents/Resources/assets/"
    if [[ -f assets/spotify_icon.png ]]; then
        cp assets/spotify_icon.png "$APP_DIR/Contents/Resources/assets/"
    fi
    if [[ -f config/widget-settings.conf ]]; then
        cp config/widget-settings.conf "$APP_DIR/Contents/Resources/widget-settings.conf"
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
    <key>NSAudioCaptureUsageDescription</key>
    <string>Wallify uses system audio only to draw the optional live waveform. Audio is not recorded or saved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Wallify uses Apple Events to display track metadata and control music playback.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Wallify needs Accessibility access to intercept media keys (F7/F8/F9) and redirect them to Spotify or your chosen source instead of Apple Music.</string>
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
    codesign --deep "${SIGN_ARGS[@]}" "$APP_DIR"

    # Verify signature
    codesign --verify --deep --strict "$APP_DIR"
    echo -e "  ${GREEN}✓${RESET} Bundle signed and verified successfully."
    if [[ "$(python3 scripts/build-tools.py package-signature "$BUILD_ROOT")" != "$PACKAGE_SIGNATURE" ]]; then
        echo "Build inputs changed while packaging; previous app preserved. Retry packaging." >&2
        exit 1
    fi
    python3 scripts/build-tools.py publish "$APP_DIR" "$FINAL_APP"
    APP_DIR="$FINAL_APP"
    python3 scripts/build-tools.py stamp "$APP_DIR" "$PACKAGE_SIGNATURE"
    rm -rf "$STAGING_DIR"
    STAGING_DIR=""
fi

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
    DMG_PATH="build/${APP_NAME}.dmg"
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
elif [[ "$DO_KICKSTART" == true ]]; then
    ./scripts/relaunch.sh
fi

APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo -e "${GREEN}${BOLD}Done!${RESET} ${APP_NAME}.app created at ${CYAN}${APP_DIR}${RESET} (${APP_SIZE})"
