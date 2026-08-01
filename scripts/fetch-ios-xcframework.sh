#!/usr/bin/env bash
#
# Fetch + verify the llama.cpp iOS xcframework (native inference libs) for
# Dhruva, and vendor it for manual CocoaPods integration (llama_cpp_dart is
# not a Flutter plugin — no `flutter:` key in its pubspec — so CocoaPods
# autodiscovery never finds it; app/ios/Podfile references this vendored copy
# directly via `pod 'llama_cpp', :path => ...`).
#
# Provenance (why this exact artifact):
#   Source repo  : github.com/netdur/llama_cpp_dart
#   Release       : v0.9.0-dev.9  (asset: llama-xcframework.zip)
#   Release commit: 1a8c7563cb5382e23bcd20dc5720fc8d8099ec58
#   Our engine pin: c6e37785835a189261fab28e53386e4e954f3e42  (ENGINE PIN, DECISIONS.md)
#   Relationship  : our pin is 2 commits AHEAD of the release tag; both are
#                   pure-Dart (worker.dart cancel fix #106, probe_cancel #105) and
#                   touch NO native code. The xcframework contains only compiled
#                   Mach-O binaries, so it is native-identical to what our pin
#                   would build. => download, not rebuild. (Rebuild path: clone
#                   the pin, tool/build_apple_xcframework.sh with Xcode — only
#                   needed if a future pin bumps native code.)
#   Zip sha256    : 9961403cf5936a380c698a3509f3377f830a9a586d44383970e6f9f010dd8af1
#   Zip contains  : llama.xcframework/{ios-arm64,ios-arm64-simulator,macos-arm64}
#   Slices kept   : ios-arm64, ios-arm64-simulator only. macos-arm64 is DROPPED
#                   (32MB of the 53MB zip) — macOS dev/test never uses this
#                   xcframework; it loads raw dylibs from app/.dev-native/macos
#                   (see native_test_config.dart), so the pod's macOS slice
#                   would be permanent dead weight in git history.
#   Vendored size : ~22MB (ios-arm64 + ios-arm64-simulator only)
#   Podspec       : copied unmodified from the pin (llama_cpp.podspec) — it
#                   already declares s.source = {:path => '.'} and
#                   s.vendored_frameworks = 'build/apple/llama.xcframework',
#                   matching this script's target layout.
#
# The vendored tree is committed, so a normal checkout needs nothing. Run this
# only to re-fetch or to verify integrity of the committed copy. Idempotent.
#
# Usage: scripts/fetch-ios-xcframework.sh [--verify-only]
set -euo pipefail

REPO="netdur/llama_cpp_dart"
TAG="v0.9.0-dev.9"
ASSET="llama-xcframework.zip"
ZIP_SHA256="9961403cf5936a380c698a3509f3377f830a9a586d44383970e6f9f010dd8af1"
DROP_SLICES=("macos-arm64")

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/app/ios/Vendor/llama_cpp"
XCFRAMEWORK_DIR="$VENDOR_DIR/build/apple/llama.xcframework"
STAMP="$VENDOR_DIR/.source-sha256"

sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

if [[ "${1:-}" == "--verify-only" ]]; then
  [[ -d "$XCFRAMEWORK_DIR" ]] || { echo "error: $XCFRAMEWORK_DIR missing" >&2; exit 1; }
  [[ -f "$STAMP" && "$(cat "$STAMP")" == "$ZIP_SHA256" ]] || {
    echo "error: $VENDOR_DIR not sourced from verified $ASSET ($ZIP_SHA256)" >&2
    exit 1
  }
  echo "xcframework ok: sourced from $ASSET ($ZIP_SHA256)"
  exit 0
fi

# Already present and correct? Nothing to do.
if [[ -d "$XCFRAMEWORK_DIR" && -f "$STAMP" && "$(cat "$STAMP")" == "$ZIP_SHA256" ]]; then
  echo "xcframework already present and verified: $ASSET"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "downloading $ASSET from $REPO@$TAG ..."
gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$WORK" --clobber

ZIP="$WORK/$ASSET"
got="$(sha_of "$ZIP")"
[[ "$got" == "$ZIP_SHA256" ]] || { echo "error: sha256 mismatch (expected $ZIP_SHA256, got $got)" >&2; exit 1; }
echo "zip fetched + verified: $ASSET ($ZIP_SHA256)"

unzip -q "$ZIP" -d "$WORK/extracted"

# Drop unneeded slices + repair Info.plist so the xcframework stays internally
# consistent (a stale AvailableLibraries entry pointing at a deleted slice
# breaks Xcode's xcframework validation).
PLIST="$WORK/extracted/llama.xcframework/Info.plist"
for slice in "${DROP_SLICES[@]}"; do
  rm -rf "$WORK/extracted/llama.xcframework/$slice"
  /usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$PLIST" >/dev/null 2>&1 || continue
  count="$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$PLIST" | grep -c 'LibraryIdentifier')"
  for ((i = count - 1; i >= 0; i--)); do
    id="$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$PLIST" 2>/dev/null || true)"
    [[ "$id" == "$slice" ]] && /usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:$i" "$PLIST"
  done
done

mkdir -p "$VENDOR_DIR/build/apple"
rm -rf "$XCFRAMEWORK_DIR"
cp -R "$WORK/extracted/llama.xcframework" "$XCFRAMEWORK_DIR"
echo "$ZIP_SHA256" > "$STAMP"

# llama_cpp.podspec + LICENSE are NOT part of the GH release zip — they live
# in the pinned llama_cpp_dart git source (pubspec.yaml `ref`) and are
# committed statically alongside this vendored xcframework. Re-copy them only
# if the engine pin changes (see app/ios/Vendor/llama_cpp/llama_cpp.podspec).

echo "xcframework vendored + verified: $ASSET -> $VENDOR_DIR (slices: $(ls "$XCFRAMEWORK_DIR"))"
