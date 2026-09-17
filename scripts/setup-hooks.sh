#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

HOOK_DIR=".git/hooks"
PRE_COMMIT_HOOK="${HOOK_DIR}/pre-commit"

echo -e "${BOLD}${CYAN}==>${RESET} ${BOLD}Setting up Git Hooks...${RESET}"

if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Not inside a Git repository. Run 'git init' first.${RESET}" >&2
    exit 1
fi

mkdir -p "$HOOK_DIR"

cat > "$PRE_COMMIT_HOOK" <<'EOF'
#!/usr/bin/env bash
set -e

# Find all staged .zig files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "\.zig$" || true)

if [[ -n "$STAGED_FILES" ]]; then
    echo "🎨 Formatting staged Zig files..."
    
    for FILE in $STAGED_FILES; do
        if [[ -f "$FILE" ]]; then
            zig fmt "$FILE"
            # Re-stage the file in case zig fmt modified it
            git add "$FILE"
        fi
    done
fi
EOF

chmod +x "$PRE_COMMIT_HOOK"

echo -e "  ${GREEN}✓${RESET} Pre-commit hook installed at ${PRE_COMMIT_HOOK}"
echo -e "    All staged .zig files will automatically be formatted on 'git commit'."
