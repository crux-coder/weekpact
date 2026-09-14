#!/bin/sh
set -eu
# Only archive/device release builds upload symbols; local previews stay local.
case "${CONFIGURATION:-}" in Release|Profile) ;; *) exit 0 ;; esac
case "${PLATFORM_NAME:-}" in iphoneos) ;; *) exit 0 ;; esac
weekpact_sdk="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics"
if [ ! -x "$weekpact_sdk/run" ]; then
  weekpact_sdk="$SRCROOT/../${FLUTTER_BUILD_DIR:-build}/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics"
fi
if [ ! -x "$weekpact_sdk/run" ]; then
  echo "error: Firebase Crashlytics symbol uploader is missing from resolved Swift packages."
  exit 1
fi
exec "$weekpact_sdk/run"
