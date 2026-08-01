#!/usr/bin/env bash
# Build the iOS IPA (ad-hoc signed) and upload it to Firebase App Distribution.
#
# Usage:
#   scripts/distribute-ios.sh [release-notes] [groups]
#
# Defaults: notes auto-generated from git, groups "internal-testers".
# Requires: flutter, firebase CLI authenticated to the dhruvaai-68a00 project,
# the "iPhone Distribution: GLOBAL SYNAPSE TECHNOLOGIES (9AA3ASU85Q)" signing
# identity in the login keychain, and the "dhruva" ad-hoc provisioning profile
# installed at ~/Library/Developer/Xcode/UserData/Provisioning Profiles/
# (App ID 9AA3ASU85Q.app.dhruva.mobile, 1 registered device, expires
# 2027-07-31). See app/ios/ExportOptions.plist for the export config this
# script drives (manual signing, method=ad-hoc — this Xcode's
# IDEDistribution.framework only recognizes "ad-hoc" as a command-line
# distribution-method name; it does NOT have "release-testing").
#
# NOTE: iOS bundle ID (app.dhruva.mobile) differs from Android's
# (tech.appuinside.dhruva) — the original ID could not be registered with
# Apple. Android is unaffected and already shipped under the old ID.
#
# CI later reuses this same script with a token (Loop 13 / checkpoint H3).
set -euo pipefail

FIREBASE_PROJECT="dhruvaai-68a00"
IOS_APP_ID="1:792596873288:ios:c3fe8a5329ee4e657bd87d"
GROUPS_ARG="${2:-internal-testers}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/app"

SHA="$(git rev-parse --short HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
NOTES="${1:-Dev build from $BRANCH @ $SHA — $(git log -1 --pretty=%s)}"

# Stamp a UNIQUE, monotonic build number per ship (git commit count) — same
# rationale as the Android lane (scripts/distribute.sh): a static build
# number makes App Store Connect / TestFlight-style tooling and devices
# refuse to cleanly treat a new upload as newer than the last one.
BUILD_NUMBER="$(git rev-list --count HEAD)"
BUILD_NAME="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"
echo "==> version $BUILD_NAME+$BUILD_NUMBER — flutter build ipa ($BRANCH @ $SHA)"
flutter build ipa --export-options-plist=ios/ExportOptions.plist \
  --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"

IPA_DIR="build/ios/ipa"
IPA="$(find "$IPA_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
[ -n "$IPA" ] && [ -f "$IPA" ] || { echo "IPA not found under $IPA_DIR"; exit 1; }
echo "==> Uploading $(du -h "$IPA" | cut -f1 | tr -d ' ') IPA to App Distribution ($GROUPS_ARG)"

firebase appdistribution:distribute "$IPA" \
  --app "$IOS_APP_ID" \
  --project "$FIREBASE_PROJECT" \
  --groups "$GROUPS_ARG" \
  --release-notes "$NOTES"

echo "==> Done. Testers in '$GROUPS_ARG' will get the email."
