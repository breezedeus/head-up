#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HeadUp"
BUNDLE_ID="com.king.headup"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# HEADUP_PREVIEW=1 builds a preview/debug binary: compile with -DHEADUP_DEBUG so
# high-frequency drift diagnostics are included and elevated to info-level logs.
PREVIEW_BUILD=0
if [[ "${HEADUP_PREVIEW:-0}" == "1" ]]; then
  PREVIEW_BUILD=1
fi
SWIFT_BUILD_ARGS=()
if [[ "$PREVIEW_BUILD" == "1" ]]; then
  SWIFT_BUILD_ARGS+=(-Xswiftc -DHEADUP_DEBUG)
fi

# The bundle name never carries a preview suffix: this script installs nothing and
# produces no archive, so a preview and a normal build simply replace each other at
# the same path. A preview bundle is identifiable by HeadUpPreviewBuild in its
# Info.plist and by the build message below.
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
# macOS ships bash 3.2, where `set -u` treats an empty array expansion as unbound.
# The `${a[@]+...}` guard keeps a non-preview build (empty args) working.
swift build ${SWIFT_BUILD_ARGS[@]+"${SWIFT_BUILD_ARGS[@]}"}
BUILD_DIR="$(swift build ${SWIFT_BUILD_ARGS[@]+"${SWIFT_BUILD_ARGS[@]}"} --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
if [[ "$PREVIEW_BUILD" == "1" ]]; then
  echo "Preview build: HEADUP_DEBUG enabled, verbose drift logs will be recorded."
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_CONTENTS/Resources"
cp -R "$ROOT_DIR/Sources/HeadUp/Resources/MenuBarIcons" "$APP_CONTENTS/Resources/MenuBarIcons"
if [[ -d "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" ]]; then
  cp -R "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" "$APP_CONTENTS/Resources/$RESOURCE_BUNDLE_NAME"
else
  echo "SwiftPM resource bundle is missing: $BUILD_DIR/$RESOURCE_BUNDLE_NAME" >&2
  exit 2
fi
if [[ -f "$ROOT_DIR/Resources/HeadUp.icns" ]]; then
  cp "$ROOT_DIR/Resources/HeadUp.icns" "$APP_CONTENTS/Resources/HeadUp.icns"
fi

# System-facing app names and permission descriptions follow the system language.
for app_language in en zh-Hans; do
  mkdir -p "$APP_CONTENTS/Resources"/"$app_language.lproj"
  cp "$ROOT_DIR/Sources/HeadUp/Resources/$app_language.lproj/InfoPlist.strings" "$APP_CONTENTS/Resources"/"$app_language.lproj/InfoPlist.strings"
done

if [[ "$PREVIEW_BUILD" == "1" ]]; then
  PREVIEW_PLIST_LINE=$'\t<key>HeadUpPreviewBuild</key><true/>'
else
  PREVIEW_PLIST_LINE=""
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
  <string>HeadUp</string>
  <key>CFBundleDisplayName</key>
  <string>HeadUp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
$PREVIEW_PLIST_LINE
  <key>CFBundleIconFile</key>
  <string>HeadUp</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.healthcare-fitness</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMotionUsageDescription</key>
  <string>HeadUp uses AirPods head motion data for posture reminders and to cover screens when you look away.</string>
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
  if [[ "${HEADUP_SETTINGS_SNAPSHOT:-}" == "1" ]]; then
    open_args+=(--env "HEADUP_SETTINGS_SNAPSHOT=1")
  fi
  /usr/bin/open "${open_args[@]}" "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    if [[ "$PREVIEW_BUILD" == "1" ]]; then
      echo "Built PREVIEW $APP_BUNDLE ($VERSION, build $BUILD_NUMBER) with debug drift logging"
    else
      echo "Built $APP_BUNDLE ($VERSION, build $BUILD_NUMBER)"
    fi
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    log_level_args=(--info)
    [[ "$PREVIEW_BUILD" == "1" ]] && log_level_args+=(--debug)
    /usr/bin/log stream "${log_level_args[@]}" --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    log_level_args=(--info)
    [[ "$PREVIEW_BUILD" == "1" ]] && log_level_args+=(--debug)
    /usr/bin/log stream "${log_level_args[@]}" --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2
    echo "       set HEADUP_PREVIEW=1 to compile a preview build with verbose drift debug logs" >&2
    exit 2
    ;;
esac
