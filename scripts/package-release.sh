#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <version>\n' "$0" >&2
  printf 'example: %s 0.1.0\n' "$0" >&2
}

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  usage
  exit 64
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/PTK.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
STAGING_DIR="$DIST_DIR/dmg-staging"
ZIP_PATH="$DIST_DIR/PTK-macos-$VERSION-unsigned.zip"
DMG_PATH="$DIST_DIR/PTK-macos-$VERSION-unsigned.dmg"
BINARY_PATH="$ROOT_DIR/macos/.build/release/PTK"

case "$VERSION" in
  *[!0-9A-Za-z._-]*)
    printf 'error: version contains unsupported characters: %s\n' "$VERSION" >&2
    exit 64
    ;;
esac

rm -rf "$APP_DIR" "$STAGING_DIR" "$ZIP_PATH" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_DIR"

swift build --package-path "$ROOT_DIR/macos" -c release --product PTK
cp "$BINARY_PATH" "$MACOS_DIR/PTK"
chmod +x "$MACOS_DIR/PTK"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>PTK</string>
  <key>CFBundleIdentifier</key>
  <string>dev.pgkim.ptk</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PTK</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cp -R "$APP_DIR" "$STAGING_DIR/PTK.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "PTK $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGING_DIR"

printf 'Created %s\n' "$APP_DIR"
printf 'Created %s\n' "$ZIP_PATH"
printf 'Created %s\n' "$DMG_PATH"
