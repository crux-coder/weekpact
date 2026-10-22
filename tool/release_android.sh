#!/usr/bin/env bash
# Build a signed Android App Bundle and, with --track, upload it to Google Play.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
usage() {
  cat <<'HELP'
Usage: ./tool/release_android.sh [--track internal|production] [--build-number N]
                                 [--env FILE] [--no-open] [--skip-version-check]

Build a release .aab signed with the upload keystore from android/key.properties.
Version comes from pubspec.yaml. The version code is minutes elapsed since
2026-01-01 UTC, the same scheme release_ios.sh uses, so any machine and any
clean checkout produces a higher code than the last release without sharing
state; it is raised past the local counter, previous bundles, or pubspec build
number when one of those is ahead.
Defaults to .env.json when present, otherwise .env. Relative paths use repo root.
Use --build-number N to choose one explicitly; it must still exceed the local
maximum and stay under Play's cap of 2100000000.
Without --track the bundle is only built; upload it in Play Console yourself.
With --track the bundle is uploaded with fastlane supply using the Play service
account key in $PLAY_JSON_KEY, or the only .json in ~/.config/weekpact. Store
listing text and screenshots are left alone. production asks for confirmation
first when run from a terminal.
  pnpm release-android-test   build and upload to internal testing
  pnpm release-android        build and upload to production
Except on the internal track, the version must be newer than the Android
release marked live in public.app_releases, or installed apps are never told
about it; raise it with pnpm bump-version. --skip-version-check builds without
asking the backend. Once the release is live on Google Play, run
pnpm mark-released android.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
source tool/release_version.sh
ENV_FILE=".env"
[[ ! -f .env.json ]] || ENV_FILE=".env.json"
BUILD_NUMBER=""
REVEAL_BUNDLE=true
CHECK_VERSION=true
TRACK=""
PACKAGE_NAME=dev.codepeaktrail.weekpact
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --env|--build-number|--track)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
      case "$1" in
        --env) ENV_FILE="$2" ;;
        --build-number) BUILD_NUMBER="$2" ;;
        --track) TRACK="$2" ;;
      esac
      shift 2 ;;
    --no-open) REVEAL_BUNDLE=false; shift ;;
    --skip-version-check) CHECK_VERSION=false; shift ;;
    *) fail "Unknown option: $1 (use --help)" ;;
  esac
done
command -v flutter >/dev/null || fail 'Add Flutter to your PATH first.'
if [[ -n "$TRACK" ]]; then
  [[ "$TRACK" == internal || "$TRACK" == production ]] || fail '--track must be internal or production.'
  command -v fastlane >/dev/null || fail 'Uploading needs fastlane: brew install fastlane'
  PLAY_JSON_KEY="${PLAY_JSON_KEY:-}"
  if [[ -z "$PLAY_JSON_KEY" ]]; then
    keys=("$HOME"/.config/weekpact/*.json)
    [[ ${#keys[@]} -eq 1 && -f "${keys[0]}" ]] || fail 'Set PLAY_JSON_KEY to the Play service account key, or keep exactly one .json in ~/.config/weekpact.'
    PLAY_JSON_KEY="${keys[0]}"
  fi
  [[ -f "$PLAY_JSON_KEY" ]] || fail "Play service account key not found: $PLAY_JSON_KEY"
  case "$PLAY_JSON_KEY" in "$ROOT"/*) fail 'Keep the Play service account key outside the repo.' ;; esac
  # Production goes to every user after review, so check before spending a build.
  if [[ "$TRACK" == production && -t 0 ]]; then
    read -r -p 'Build and send this release to PRODUCTION? Type yes: ' answer
    [[ "$answer" == yes ]] || fail 'Cancelled.'
  fi
fi
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
# Internal testers install from Play directly and are never prompted.
if "$CHECK_VERSION" && [[ "$TRACK" != internal ]]; then require_new_version android "$VERSION"; fi
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
if [[ -z "$TRACK" ]]; then
  printf '%s\n' 'In Play Console (https://play.google.com/console):' '1. Open WeekPact → Testing → Internal testing (or Production) → Create new release.' '2. Upload this .aab and add release notes.' '3. Review the release and roll it out.' '4. Internal testers get the build within minutes; Production and closed tracks go through review first.' "5. Once $VERSION is live in production: pnpm mark-released android"
  if "$REVEAL_BUNDLE" && [[ "$(uname -s)" == Darwin ]]; then open -R "$DEST"; fi
  exit 0
fi
printf 'Uploading to the %s track\n' "$TRACK"
fastlane supply \
  --aab "$DEST" \
  --track "$TRACK" \
  --release_status completed \
  --json_key "$PLAY_JSON_KEY" \
  --package_name "$PACKAGE_NAME" \
  --skip_upload_apk \
  --skip_upload_metadata \
  --skip_upload_changelogs \
  --skip_upload_images \
  --skip_upload_screenshots
if [[ "$TRACK" == internal ]]; then
  printf '\nUploaded. Internal testers get WeekPact %s (%s) within minutes.\n' "$VERSION" "$BUILD_NUMBER"
else
  printf '\nUploaded. WeekPact %s (%s) is sent for review and goes live once approved.\n' "$VERSION" "$BUILD_NUMBER"
  printf 'Once it is live, tell installed apps: pnpm mark-released android\n'
fi
