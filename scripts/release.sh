#!/usr/bin/env bash
# Publishes a Wallify release on GitHub: ./scripts/release.sh 1.1.0
# Bumps VERSION, runs the tests, builds the DMG, commits, tags v<version>, pushes and creates the
# GitHub release. Running copies of Wallify find it on their next daily update check.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

version="${1:-}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Usage: ./scripts/release.sh <version>, for example 1.1.0" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || { echo "Tag v$version already exists." >&2; exit 1; }
command -v gh >/dev/null || { echo "The GitHub CLI (gh) is required: brew install gh" >&2; exit 1; }
current="$(tr -d '[:space:]' < VERSION)"
[[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" == "$version" && "$current" != "$version" ]] ||
    { echo "Version $version must be newer than the current $current." >&2; exit 1; }

bash scripts/build.sh --test
printf '%s\n' "$version" > VERSION
bash scripts/package-app.sh --build --dmg
git commit -m "Release $version" -- VERSION
git tag "v$version"
git push origin HEAD "v$version"
gh release create "v$version" "build/Wallify.dmg" --title "Wallify $version" --generate-notes
echo "Published Wallify $version."
