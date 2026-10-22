#!/usr/bin/env bash
# Raise the X.Y.Z version in pubspec.yaml for the next store release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
usage() {
  cat <<'HELP'
Usage: ./tool/bump_version.sh [patch|minor|major|X.Y.Z]

Raise the version in pubspec.yaml; patch is the default. The build number
after + is left alone, since the release scripts choose their own. Every store
release needs a new version: the update prompt compares X.Y.Z only, and the
release scripts refuse one that is not newer than the live release.
The change is left for you to commit.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
source tool/release_version.sh

PART=patch
[[ $# -le 1 ]] || fail 'Give one of patch, minor, major or X.Y.Z.'
case "${1:-patch}" in
  --help|-h) usage; exit 0 ;;
  patch|minor|major) PART="${1:-patch}" ;;
  *) [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Unknown option: $1 (use --help)"; PART="$1" ;;
esac

VERSION_LINE="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' pubspec.yaml)"
VERSION="${VERSION_LINE%%+*}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use version: X.Y.Z+N in pubspec.yaml.'
IFS=. read -r major minor patch <<<"$VERSION"
case "$PART" in
  patch) NEXT="$major.$minor.$((patch + 1))" ;;
  minor) NEXT="$major.$((minor + 1)).0" ;;
  major) NEXT="$((major + 1)).0.0" ;;
  *) NEXT="$PART" ;;
esac
version_newer "$NEXT" "$VERSION" || fail "$NEXT is not newer than $VERSION."

BUILD="${VERSION_LINE#"$VERSION"}"
sed -i.bak -E "s/^version:[[:space:]]*[^[:space:]#]+/version: $NEXT$BUILD/" pubspec.yaml
rm -f pubspec.yaml.bak
printf 'pubspec.yaml: %s -> %s\n' "$VERSION" "$NEXT"
for platform in ios android; do
  if live="$(live_release_version "$platform")"; then
    printf 'Live %s: %s\n' "$platform" "$live"
  fi
done
printf 'Commit pubspec.yaml, then release.\n'
