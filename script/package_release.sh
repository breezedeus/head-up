#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HeadUp"
BUNDLE_ID="com.king.headup"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${HEADUP_BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}"
SIGNING_IDENTITY="${HEADUP_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${HEADUP_NOTARY_PROFILE:-}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DSYM_ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dSYM.zip"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"

require_xcbuild_for_universal_build() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"

  local xcbuild_path=""

  if [[ "$developer_dir" == */Contents/Developer ]]; then
    local xcode_app_dir="${developer_dir%/Contents/Developer}"
    xcbuild_path="$xcode_app_dir/Contents/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"
  elif [[ -n "$developer_dir" ]]; then
    xcbuild_path="${developer_dir%/CommandLineTools}/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"
  fi

  # Some Xcode installations do not expose the internal xcbuild binary at the
  # expected framework path. In that case, xcodebuild is the public supported
  # frontend and is enough for SwiftPM universal release builds.
  if [[ -n "$xcbuild_path" && -x "$xcbuild_path" ]]; then
    return 0
  fi

  if xcrun --find xcodebuild >/dev/null 2>&1; then
    return 0
  fi

  cat >&2 <<EOF

The universal SwiftPM release build requires Xcode's build tools, but neither
the internal xcbuild tool nor the public xcodebuild tool was found.

Selected developer directory:
  ${developer_dir:-<none>}

Install the full Xcode app, then select it with:
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept

Then rerun:
  cd "$ROOT_DIR"
  HEADUP_SIGNING_IDENTITY="${HEADUP_SIGNING_IDENTITY:--}" ./script/package_release.sh

EOF
  exit 2
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "HEADUP_SIGNING_IDENTITY is required for a public release." >&2
  exit 2
fi

require_xcbuild_for_universal_build

if [[ ! -f "$ROOT_DIR/Resources/HeadUp.icns" ]]; then
  echo "Resources/HeadUp.icns is required for a public release." >&2
  exit 2
fi

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

mkdir -p "$RELEASE_DIR"
rm -rf "$APP_BUNDLE"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256" "$DSYM_ZIP_PATH" "$DSYM_ZIP_PATH.sha256"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"
cp -R "$ROOT_DIR/Sources/HeadUp/Resources/MenuBarIcons" "$APP_RESOURCES/MenuBarIcons"
if [[ -d "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" ]]; then
  cp -R "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
else
  echo "SwiftPM resource bundle is missing: $BUILD_DIR/$RESOURCE_BUNDLE_NAME" >&2
  exit 2
fi

cp "$ROOT_DIR/Resources/HeadUp.icns" "$APP_RESOURCES/HeadUp.icns"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>抬头</string>
  <key>CFBundleDisplayName</key><string>抬头</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>HeadUp</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSMotionUsageDescription</key><string>抬头需要读取 AirPods 的头部运动数据，以判断你是否持续低头。</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vv --type execute "$APP_BUNDLE"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
else
  echo "HEADUP_NOTARY_PROFILE is unset; the signed build was not notarized." >&2
fi

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

if [[ -d "$BUILD_DIR/$APP_NAME.dSYM" ]]; then
  ditto -c -k --keepParent "$BUILD_DIR/$APP_NAME.dSYM" "$DSYM_ZIP_PATH"
  shasum -a 256 "$DSYM_ZIP_PATH" > "$DSYM_ZIP_PATH.sha256"
fi

echo "$ZIP_PATH"
