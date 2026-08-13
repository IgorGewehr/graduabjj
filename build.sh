#!/bin/bash

# BJJEasy - Flutter Build Script
#
# Usage:
#   ./build.sh aab        # only Android App Bundle (Play Store)
#   ./build.sh apk        # only signed APK (sideload)
#   ./build.sh ipa        # only iOS archive (App Store / TestFlight)
#   ./build.sh all        # AAB + APK + IPA, sequenced (~15 min on this box)
#   ./build.sh            # same as "all"
#
# Artifacts are copied to dist/ with the version pulled from pubspec.yaml,
# matching the existing naming scheme: graduabjj-<version>-<build>.<ext>.

set -euo pipefail

# Common --dart-define flags reused by every build target.
# Only public configuration belongs in a distributed Flutter binary. Billing
# notifications are dispatched by authenticated Cloud Functions; notification
# server credentials must be configured in Firebase Secret Manager.
DEFINES=(
  --dart-define=APP_BASE_URL=https://arpjj-76350.web.app
  --dart-define=API_BASE_URL=https://arpjj-76350.web.app/api
)

# Parse `version: X.Y.Z+N` from pubspec.yaml.
VERSION_LINE=$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION_LINE%+*}"
BUILD_NUM="${VERSION_LINE#*+}"
ARTIFACT_BASE="graduabjj-${VERSION_NAME}-${BUILD_NUM}"

mkdir -p dist

target="${1:-all}"

build_aab() {
  echo "=== building AAB (${ARTIFACT_BASE}.aab) ==="
  flutter build appbundle "${DEFINES[@]}"
  cp build/app/outputs/bundle/release/app-release.aab "dist/${ARTIFACT_BASE}.aab"
  echo "wrote dist/${ARTIFACT_BASE}.aab"
}

build_apk() {
  echo "=== building APK (${ARTIFACT_BASE}.apk) ==="
  flutter build apk --release "${DEFINES[@]}"
  cp build/app/outputs/flutter-apk/app-release.apk "dist/${ARTIFACT_BASE}.apk"
  echo "wrote dist/${ARTIFACT_BASE}.apk"
}

build_ipa() {
  echo "=== building IPA (${ARTIFACT_BASE}.ipa) ==="
  flutter build ipa --release "${DEFINES[@]}"
  # Flutter writes the archive into build/ios/ipa/<name>.ipa
  shopt -s nullglob
  ipa_files=(build/ios/ipa/*.ipa)
  if [[ ${#ipa_files[@]} -eq 0 ]]; then
    echo "no .ipa produced — check Xcode signing output above" >&2
    return 1
  fi
  cp "${ipa_files[0]}" "dist/${ARTIFACT_BASE}.ipa"
  echo "wrote dist/${ARTIFACT_BASE}.ipa"
}

case "$target" in
  aab) build_aab ;;
  apk) build_apk ;;
  ipa) build_ipa ;;
  all)
    build_aab
    build_apk
    build_ipa
    ;;
  *)
    echo "unknown target: $target (use aab|apk|ipa|all)" >&2
    exit 2
    ;;
esac
