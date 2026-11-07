#!/usr/bin/env bash
# Starts a Wallify release: ./scripts/release.sh 1.1.0
# Runs the tests, bumps VERSION, commits, tags v<version> and pushes. The Release workflow
# (.github/workflows/release.yml) then builds the DMG and publishes the GitHub release.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

version="${1:-}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Usage: ./scripts/release.sh <version>, for example 1.1.0" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || { echo "Tag v$version already exists." >&2; exit 1; }
current="$(tr -d '[:space:]' < VERSION)"
[[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" == "$version" && "$current" != "$version" ]] ||
    { echo "Version $version must be newer than the current $current." >&2; exit 1; }

bash scripts/build.sh --test
printf '%s\n' "$version" > VERSION
git commit -m "Release $version" -- VERSION
git tag "v$version"
git push origin HEAD "v$version"
echo "Pushed v$version; the Release workflow publishes it: https://github.com/n0thhhing/wallify/actions"
