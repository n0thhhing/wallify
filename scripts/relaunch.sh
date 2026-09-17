#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

AGENT="${WALLIFY_LAUNCH_AGENT:-com.levi.spotify-panel}"

echo -e "${BOLD}${CYAN}==>${RESET} ${BOLD}Relaunching Wallify LaunchAgent...${RESET}"
echo -e "  ${CYAN}•${RESET} Kickstarting service: ${AGENT}"

if ! launchctl kickstart -k "gui/$(id -u)/${AGENT}" 2>/dev/null; then
    echo -e "  ${CYAN}•${RESET} Agent not loaded. Bootstrapping..."
    PLIST="$HOME/Library/LaunchAgents/${AGENT}.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl bootstrap "gui/$(id -u)" "$PLIST"
        launchctl kickstart -k "gui/$(id -u)/${AGENT}" 2>/dev/null || true
    else
        echo -e "${RED}Error: ${PLIST} not found. Cannot bootstrap.${RESET}" >&2
        exit 1
    fi
fi

echo -e "  ${GREEN}✓${RESET} Service restarted successfully."
