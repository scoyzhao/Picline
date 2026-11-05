#!/bin/bash
# Build with this Mac's installed compiler without changing its developer tools.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="$PWD/build/local"
APP="$OUTPUT/Picline.app"
mkdir -p "$OUTPUT" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
TEST_SOURCES=()
for source in Sources/Tendedero/*.swift; do
  SOURCES+=("$source")
  if [[ "$source" != */main.swift ]]; then TEST_SOURCES+=("$source"); fi
done

if [[ "${1:-app}" == check ]]; then
  xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-name Tendedero \
    "${TEST_SOURCES[@]}" scripts/check-copy-all.swift -o "$OUTPUT/check-copy-all"
  exec "$OUTPUT/check-copy-all" "${@:2}"
fi

xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" -module-name Tendedero \
  "${SOURCES[@]}" -o "$APP/Contents/MacOS/Picline"
# Preserve this installation's application identity and existing preferences.
cp /Applications/Picline.app/Contents/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.2.9' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 28' "$APP/Contents/Info.plist"
cp /Applications/Picline.app/Contents/Resources/Picline.icns "$APP/Contents/Resources/Picline.icns"
for resource in Sources/Tendedero/Resources/*.lproj; do cp -R "$resource" "$APP/Contents/Resources/"; done
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp NOTICE "$APP/Contents/Resources/NOTICE.txt"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
