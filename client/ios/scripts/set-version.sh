#!/bin/sh
# Derive the app version from git, the same way the Android build does
# (client/android/app/build.gradle.kts: `git describe --tags --dirty=-dirty`, leading "v" stripped).
#
#   PsTotpVersionLabel          full label, identical to Android's versionName  e.g. 0.9.2-25-g7043b5a
#   CFBundleShortVersionString  numeric tag only (the App Store rejects anything else)  e.g. 0.9.2
#   CFBundleVersion             commit count (monotonic, so every TestFlight build is unique)
#
# Falls back to 1.0.0 / 1 when git or tags are unavailable (e.g. a source tarball).
set -eu

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
cd "${SRCROOT}"

label=""; short=""; build=""
if describe=$(git describe --tags --dirty=-dirty 2>/dev/null) && [ -n "$describe" ]; then
  label=${describe#v}
  short=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep -Eo '^[0-9]+(\.[0-9]+){0,2}' || true)
fi
build=$(git rev-list --count HEAD 2>/dev/null || true)

short=${short:-1.0.0}
build=${build:-1}
label=${label:-$short}

set_key() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"; }
set_key CFBundleShortVersionString "$short"
set_key CFBundleVersion "$build"
set_key PsTotpVersionLabel "$label"
echo "PsTotp version: $label (short $short, build $build)"
