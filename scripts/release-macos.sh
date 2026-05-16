#!/usr/bin/env bash

# CodexMonitor macOS 发布脚本。
# 该脚本负责生成用户可直接下载安装的 DMG，并完成 Developer ID 签名、公证和 staple。
# 用法：
#   scripts/release-macos.sh 1.0.1

set -euo pipefail

VERSION="${1:-1.0.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CodexMonitor.xcodeproj"
SCHEME="CodexMonitor"
CONFIGURATION="Release"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST_DIR="$ROOT_DIR/dist/release"
BUILD_DIR="$ROOT_DIR/Build/ReleasePackage"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$BUILD_DIR/Products"
INTERMEDIATES_DIR="$BUILD_DIR/Intermediates.noindex"
STAGING_DIR="$DIST_DIR/staging"
APP_NAME="CodexMonitor.app"
APP_PATH="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/CodexMonitor-$VERSION.dmg"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-$ROOT_DIR/scripts/assets/installer_background.jpg}"

# 签名和公证参数参考 /Users/harry/Projects/tauri/desktop-v1.zenai.bot/ci/mac/build.ts。
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: ZENARKFLOW PTE. LTD. (KN2J5SSSCM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ZENARKFLOW_NOTARIZE_PROFILE}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-KN2J5SSSCM}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '缺少命令：%s\n' "$1" >&2
    exit 1
  fi
}

log "检查构建依赖..."
require_command xcodebuild
require_command codesign
require_command xcrun
require_command create-dmg

if [[ ! -f "$BACKGROUND_IMAGE" ]]; then
  printf 'DMG 背景图不存在：%s\n' "$BACKGROUND_IMAGE" >&2
  exit 1
fi

log "准备输出目录：$DIST_DIR"
rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

log "构建 $SCHEME $VERSION..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  SYMROOT="$PRODUCTS_DIR" \
  OBJROOT="$INTERMEDIATES_DIR" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  build

SOURCE_APP="$PRODUCTS_DIR/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$SOURCE_APP" ]]; then
  printf '构建产物不存在：%s\n' "$SOURCE_APP" >&2
  exit 1
fi

log "复制 app 到发布目录..."
ditto "$SOURCE_APP" "$APP_PATH"

log "使用 Developer ID 签名 app..."
codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n '/Authority=/p;/TeamIdentifier=/p'

log "创建 DMG..."
cp -R "$APP_PATH" "$STAGING_DIR/"
rm -f "$DMG_PATH"
create-dmg \
  --volname "CodexMonitor $VERSION" \
  --background "$BACKGROUND_IMAGE" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 96 \
  --icon "$APP_NAME" 160 190 \
  --app-drop-link 430 190 \
  "$DMG_PATH" \
  "$STAGING_DIR"

log "签名 DMG..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

log "提交 Apple 公证：$(basename "$DMG_PATH")"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

log "Staple DMG 公证票据..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

log "Gatekeeper 评估 DMG..."
# DMG 属于安装分发物，使用 install 类型评估；open 类型在部分 macOS 版本会返回 Insufficient Context。
spctl -a -vv -t install "$DMG_PATH"

log "发布产物已生成：$DMG_PATH"
