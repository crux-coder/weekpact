#!/usr/bin/env bash
# Build a signed Android App Bundle locally; the Play Console upload is manual.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
usage() {
  cat <<'HELP'
Usage: ./tool/release_android.sh [--build-number N] [--env FILE] [--no-open]

Build a release .aab signed with the upload keystore from android/key.properties.
Version comes from pubspec.yaml. The version code is minutes elapsed since
2026-01-01 UTC, the same scheme release_ios.sh uses, so any machine and any
clean checkout produces a higher code than the last release without sharing
state; it is raised past the local counter, previous bundles, or pubspec build
number when one of those is ahead.
Defaults to .env.json when present, otherwise .env. Relative paths use repo root.
Use --build-number N to choose one explicitly; it must still exceed the local
maximum and stay under Play's cap of 2100000000.
No upload or Play Console submission is performed by this script.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
ENV_FILE=".env"
[[ ! -f .env.json ]] || ENV_FILE=".env.json"
BUILD_NUMBER=""
REVEAL_BUNDLE=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --env|--build-number)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
      if [[ "$1" == --env ]]; then ENV_FILE="$2"; else BUILD_NUMBER="$2"; fi
      shift 2 ;;
    --no-open) REVEAL_BUNDLE=false; shift ;;
    *) fail "Unknown option: $1 (use --help)" ;;
  esac
done
command -v flutter >/dev/null || fail 'Add Flutter to your PATH first.'
command -v unzip >/dev/null || fail 'unzip is required to verify the bundle signature.'
[[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Create the app configuration from .env.example."
[[ -f android/key.properties ]] || fail 'Missing android/key.properties. Play rejects debug-signed bundles; see android/key.properties.example.'
STORE_FILE="$(sed -nE 's/^storeFile=[[:space:]]*//p' android/key.properties | tail -n1)"
[[ -n "$STORE_FILE" ]] || fail 'android/key.properties has no storeFile.'
[[ "$STORE_FILE" == /* ]] || STORE_FILE="android/$STORE_FILE"
[[ -f "$STORE_FILE" ]] || fail "Upload keystore not found: $STORE_FILE"
VERSION_LINE="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' pubspec.yaml)"
VERSION="${VERSION_LINE%%+*}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use version: X.Y.Z+N in pubspec.yaml.'
COUNTER=.dart_tool/android-release-build-number
RELEASES=build/android/releases
highest=0
previous_codes="$(ls "$RELEASES" 2>/dev/null | sed -nE 's/^WeekPact-[0-9.]+-([0-9]+)\.aab$/\1/p' || true)"
for candidate in "${VERSION_LINE#*+}" "$(cat "$COUNTER" 2>/dev/null || true)" $previous_codes; do
  if [[ "$candidate" =~ ^[0-9]{1,10}$ ]]; then
    number=$((10#$candidate))
    if (( number > highest )); then highest=$number; fi
  fi
done
# Same clock as the iOS script: minutes since 2026-01-01 UTC only ever go up,
# agree on every machine without being stored, and stay far below Play's
# 2,100,000,000 version-code cap. The local maximum remains a floor so a code
# already used cannot be reused if the clock is behind it. Play also rejects a
# version code it has already seen, so retries after a failed upload need a
# fresh run.
if [[ -z "$BUILD_NUMBER" ]]; then
  EPOCH_2026=1767225600
  minutes=$(( ( $(date -u +%s) - EPOCH_2026 ) / 60 ))
  BUILD_NUMBER=$(( minutes > highest ? minutes : highest + 1 ))
fi
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,9}$ ]] || fail 'Build number must be a positive integer.'
(( BUILD_NUMBER > highest )) || fail "Build number must exceed the local maximum ($highest)."
(( BUILD_NUMBER < 2100000000 )) || fail 'Build number must stay below 2100000000 (Google Play limit).'
mkdir -p .dart_tool "$RELEASES"
# Reserve the number even if building fails; retries should use a fresh number.
printf '%s\n' "$BUILD_NUMBER" > "$COUNTER"
BUNDLE=build/app/outputs/bundle/release/app-release.aab
MARKER="$(mktemp "${TMPDIR:-/tmp}/weekpact-release.XXXXXX")"
trap 'rm -f "$MARKER"' EXIT
printf 'Building WeekPact %s (%s), using %s\n' "$VERSION" "$BUILD_NUMBER" "$ENV_FILE"
flutter build appbundle --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" --dart-define-from-file="$ENV_FILE"
[[ -f "$BUNDLE" && "$BUNDLE" -nt "$MARKER" ]] || fail 'No fresh bundle was produced; refusing to keep an older build.'
# Gradle signs with the debug keystore and only warns when key.properties is
# unusable, and Play rejects that upload later. The signer alias is visible in
# the bundle's signature file name, so check it here instead.
signers="$(unzip -Z1 "$BUNDLE" 'META-INF/*' | sed -nE 's#^META-INF/([^/]+)\.(RSA|DSA|EC)$#\1#p' || true)"
[[ -n "$signers" ]] || fail 'Bundle has no signature block.'
if printf '%s\n' "$signers" | grep -qx 'ANDROIDD'; then
  fail 'Bundle is signed with the Android debug keystore; check android/key.properties.'
fi
DEST="$ROOT/$RELEASES/WeekPact-$VERSION-$BUILD_NUMBER.aab"
[[ ! -e "$DEST" ]] || fail "Bundle already exists: $DEST"
cp "$BUNDLE" "$DEST"
printf '\nBundle ready: %s\nSigned by: %s\n\n' "$DEST" "$(printf '%s' "$signers" | tr '\n' ' ')"
printf '%s\n' 'In Play Console (https://play.google.com/console):' '1. Open WeekPact → Testing → Internal testing (or Production) → Create new release.' '2. Upload this .aab and add release notes.' '3. Review the release and roll it out.' '4. Internal testers get the build within minutes; Production and closed tracks go through review first.'
if "$REVEAL_BUNDLE" && [[ "$(uname -s)" == Darwin ]]; then open -R "$DEST"; fi
