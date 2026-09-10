#!/usr/bin/env bash
# Build locally; Xcode handles the final App Store Connect upload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
usage() {
  cat <<'HELP'
Usage: ./tool/release_ios.sh [--build-number N] [--env FILE] [--no-open]

Build a signed release archive and open it in Xcode Organizer.
Version comes from pubspec.yaml. The build number increments the highest
local counter, previous archive, or pubspec build number.
Defaults to .env.json when present, otherwise .env. Relative paths use repo root.
Use --build-number N if a higher build was uploaded from another machine.
No upload or App Store submission is performed by this script.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
ENV_FILE=".env"
[[ ! -f .env.json ]] || ENV_FILE=".env.json"
BUILD_NUMBER=""
OPEN_ARCHIVE=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --env|--build-number)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
      if [[ "$1" == --env ]]; then ENV_FILE="$2"; else BUILD_NUMBER="$2"; fi
      shift 2 ;;
    --no-open) OPEN_ARCHIVE=false; shift ;;
    *) fail "Unknown option: $1 (use --help)" ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || fail 'This script requires macOS and Xcode.'
command -v flutter >/dev/null || fail 'Add Flutter to your PATH first.'
xcodebuild -version >/dev/null || fail 'Select a full Xcode installation with xcode-select.'
[[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Create the app configuration from .env.example."
[[ -d ios/Runner.xcworkspace ]] || fail 'Missing ios/Runner.xcworkspace.'
VERSION_LINE="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' pubspec.yaml)"
VERSION="${VERSION_LINE%%+*}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use version: X.Y.Z+N in pubspec.yaml.'
COUNTER=.dart_tool/ios-release-build-number
ARCHIVE=build/ios/archive/Runner.xcarchive
highest=0
for candidate in "${VERSION_LINE#*+}" "$(cat "$COUNTER" 2>/dev/null || true)" "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist" 2>/dev/null || true)"; do
  if [[ "$candidate" =~ ^[0-9]{1,9}$ ]]; then
    number=$((10#$candidate))
    if (( number > highest )); then highest=$number; fi
  fi
done
if [[ -z "$BUILD_NUMBER" ]]; then BUILD_NUMBER=$((highest + 1)); fi
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,8}$ ]] || fail 'Build number must be a positive integer (up to 9 digits).'
(( BUILD_NUMBER > highest )) || fail "Build number must exceed the local maximum ($highest)."
mkdir -p .dart_tool build/ios/releases
# Reserve the number even if building fails; retries should use a fresh number.
printf '%s\n' "$BUILD_NUMBER" > "$COUNTER"
MARKER="$(mktemp "${TMPDIR:-/tmp}/weekpact-release.XXXXXX")"
trap 'rm -f "$MARKER"' EXIT
printf 'Building WeekPact %s (%s), using %s\n' "$VERSION" "$BUILD_NUMBER" "$ENV_FILE"
flutter build ipa --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" --dart-define-from-file="$ENV_FILE"
[[ -f "$ARCHIVE/Info.plist" && "$ARCHIVE/Info.plist" -nt "$MARKER" ]] || fail 'No fresh archive was produced; refusing to open an older build.'
actual="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
[[ "$actual" == "$BUILD_NUMBER" ]] || fail 'Archive build number does not match this release.'
DEST="$ROOT/build/ios/releases/WeekPact-$VERSION-$BUILD_NUMBER.xcarchive"
[[ ! -e "$DEST" ]] || fail "Archive already exists: $DEST"
ditto "$ARCHIVE" "$DEST"
printf '\nArchive ready: %s\n\n' "$DEST"
printf '%s\n' 'In Xcode Organizer:' '1. Select this WeekPact archive.' '2. Distribute App → App Store Connect → Upload (labels may vary by Xcode version).' '3. Review signing and upload.' '4. Wait for processing in App Store Connect, then use TestFlight or select the build for an App Store release.'
if "$OPEN_ARCHIVE"; then open -a Xcode "$DEST"; fi
