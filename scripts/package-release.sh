#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <display-version> <build-version>\n' "$0" >&2
  printf 'example: %s 0.5.0 42\n' "$0" >&2
}

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  usage
  exit 64
fi

DISPLAY_VERSION="$1"
BUILD_VERSION="$2"

if [[ ! "$DISPLAY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'error: display version must contain three numeric components: %s\n' "$DISPLAY_VERSION" >&2
  exit 64
fi

if [[ ! "$BUILD_VERSION" =~ ^[0-9]{1,4}(\.[0-9]{1,2}){0,2}$ ]]; then
  printf 'error: build version must contain one to three numeric components: %s\n' "$BUILD_VERSION" >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/PTK.app"
ZIP_PATH="$DIST_DIR/PTK-macos-$DISPLAY_VERSION-unsigned.zip"
DMG_PATH="$DIST_DIR/PTK-macos-$DISPLAY_VERSION-unsigned.dmg"
BINARY_PATH="$ROOT_DIR/macos/.build/release/PTK"
TEMP_DIR=""
ROLLBACK_ACTIVE=0
INSTALLED_PATHS=()
BACKUP_PATHS=()
FINAL_PATHS=("$APP_PATH" "$ZIP_PATH" "$DMG_PATH")

cleanup() {
  local status=$?
  local index

  if [[ "$ROLLBACK_ACTIVE" -eq 1 ]]; then
    for ((index = ${#INSTALLED_PATHS[@]} - 1; index >= 0; index--)); do
      rm -rf -- "${INSTALLED_PATHS[$index]}"
    done
    for ((index = 0; index < ${#BACKUP_PATHS[@]}; index++)); do
      if [[ -e "${BACKUP_PATHS[$index]}" || -L "${BACKUP_PATHS[$index]}" ]]; then
        mv -- "${BACKUP_PATHS[$index]}" "${FINAL_PATHS[$index]}"
      fi
    done
  fi

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

reject_symlinked_outputs() {
  local path

  if [[ -L "$DIST_DIR" ]]; then
    printf 'error: output directory must not be a symbolic link: %s\n' "$DIST_DIR" >&2
    exit 73
  fi

  for path in "${FINAL_PATHS[@]}"; do
    if [[ -L "$path" ]]; then
      printf 'error: output path must not be a symbolic link: %s\n' "$path" >&2
      exit 73
    fi
  done
}

reject_symlinked_outputs
TEMP_DIR="$(mktemp -d "$ROOT_DIR/.ptk-release.XXXXXX")"
OUTPUT_DIR="$TEMP_DIR/output"
STAGING_DIR="$TEMP_DIR/dmg-staging"
BACKUP_DIR="$TEMP_DIR/backup"
STAGED_APP_PATH="$OUTPUT_DIR/PTK.app"
CONTENTS_DIR="$STAGED_APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
STAGED_ZIP_PATH="$OUTPUT_DIR/$(basename "$ZIP_PATH")"
STAGED_DMG_PATH="$OUTPUT_DIR/$(basename "$DMG_PATH")"
STAGED_PATHS=("$STAGED_APP_PATH" "$STAGED_ZIP_PATH" "$STAGED_DMG_PATH")
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_DIR" "$BACKUP_DIR"

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
  <string>$DISPLAY_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$CONTENTS_DIR/Info.plist")" == "$DISPLAY_VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$CONTENTS_DIR/Info.plist")" == "$BUILD_VERSION" ]]
[[ "$(plutil -extract CFBundleExecutable raw -o - "$CONTENTS_DIR/Info.plist")" == "PTK" ]]
[[ "$(plutil -extract CFBundlePackageType raw -o - "$CONTENTS_DIR/Info.plist")" == "APPL" ]]
[[ -x "$MACOS_DIR/PTK" ]]

ditto -c -k --keepParent "$STAGED_APP_PATH" "$STAGED_ZIP_PATH"
unzip -tqq "$STAGED_ZIP_PATH"

cp -R "$STAGED_APP_PATH" "$STAGING_DIR/PTK.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "PTK $DISPLAY_VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$STAGED_DMG_PATH"
hdiutil verify "$STAGED_DMG_PATH" >/dev/null

[[ -s "$STAGED_ZIP_PATH" ]]
[[ -s "$STAGED_DMG_PATH" ]]

reject_symlinked_outputs
mkdir -p "$DIST_DIR"
ROLLBACK_ACTIVE=1

for ((index = 0; index < ${#FINAL_PATHS[@]}; index++)); do
  final_path="${FINAL_PATHS[$index]}"
  backup_path="$BACKUP_DIR/$index"
  if [[ -e "$final_path" ]]; then
    mv -- "$final_path" "$backup_path"
  fi
  BACKUP_PATHS+=("$backup_path")
  mv -- "${STAGED_PATHS[$index]}" "$final_path"
  INSTALLED_PATHS+=("$final_path")
done

ROLLBACK_ACTIVE=0

printf 'Created %s\n' "$APP_PATH"
printf 'Created %s\n' "$ZIP_PATH"
printf 'Created %s\n' "$DMG_PATH"
