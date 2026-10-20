#!/usr/bin/env bash
# Builds the "Open in Vitrine" share sheet action (extension/OpenInVitrine) without an Xcode project.
#
#   scripts/build-open-in-vitrine.sh <host Info.plist> <out dir>
#
# Writes <out dir>/OpenInVitrine.appex. Needs the iPhoneOS SDK (Xcode or xcode-select).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PLIST="${1:?usage: $0 <host Info.plist> <out dir>}"
OUT="${2:?usage: $0 <host Info.plist> <out dir>}"
NAME=OpenInVitrine
APPEX="$OUT/$NAME.appex"

rm -rf "$APPEX"
mkdir -p "$APPEX"

echo "==> building $NAME.appex"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -fobjc-arc -fapplication-extension -Os \
  -framework UIKit -framework UniformTypeIdentifiers -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/$NAME" "$ROOT/extension/OpenInVitrine/OpenInVitrine.m"

sed -e "s/HOST_BUNDLE_ID/$(plutil -extract CFBundleIdentifier raw -o - "$HOST_PLIST")/" \
    -e "s/HOST_SHORT_VERSION/$(plutil -extract CFBundleShortVersionString raw -o - "$HOST_PLIST")/" \
    -e "s/HOST_VERSION/$(plutil -extract CFBundleVersion raw -o - "$HOST_PLIST")/" \
    "$ROOT/extension/OpenInVitrine/Info.plist" > "$APPEX/Info.plist"
plutil -convert binary1 "$APPEX/Info.plist"

codesign -f -s - "$APPEX" >/dev/null 2>&1
echo "    $APPEX"
