#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HeadUp"
BUNDLE_ID="com.king.headup"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_CONTENTS/Resources"
cp -R "$ROOT_DIR/Sources/HeadUp/Resources/MenuBarIcons" "$APP_CONTENTS/Resources/MenuBarIcons"
if [[ -f "$ROOT_DIR/Resources/HeadUp.icns" ]]; then
  cp "$ROOT_DIR/Resources/HeadUp.icns" "$APP_CONTENTS/Resources/HeadUp.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>抬头</string>
  <key>CFBundleDisplayName</key>
  <string>抬头</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>HeadUp</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.healthcare-fitness</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMotionUsageDescription</key>
  <string>抬头需要读取 AirPods 的头部运动数据，以判断你是否持续低头。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Give the locally staged bundle a stable code identity. This mirrors Xcode's
# "Sign to Run Locally" behavior and is required by services such as local
# notifications even though distribution signing is not needed for development.
codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  local open_args=(-n)
  if [[ -n "${HEADUP_WELCOME_SNAPSHOT:-}" ]]; then
    open_args+=(--env "HEADUP_WELCOME_SNAPSHOT=$HEADUP_WELCOME_SNAPSHOT")
  fi
  if [[ "${HEADUP_AUTOCOMPLETE_ONBOARDING:-}" == "1" ]]; then
    open_args+=(--env "HEADUP_AUTOCOMPLETE_ONBOARDING=1")
  fi
  /usr/bin/open "${open_args[@]}" "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
