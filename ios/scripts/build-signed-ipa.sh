#!/usr/bin/env bash
# 使用自己的 Apple Developer 证书签名并导出 .ipa。
# 首次使用前需在 Xcode 中登录 Apple ID，并确保已生成开发证书与描述文件。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：未找到 xcodebuild。请在 macOS + Xcode 环境中运行此脚本。" >&2
  exit 1
fi

if [ -z "${TEAM_ID:-}" ]; then
  echo "错误：请通过环境变量提供 Team ID，例如：" >&2
  echo "  TEAM_ID=ABCD123456 ./scripts/build-signed-ipa.sh" >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.scanauth.totpscan}"
METHOD="${METHOD:-development}"

BUILD_DIR="$ROOT/build-signed"
ARCHIVE_PATH="$BUILD_DIR/TotpScan.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 归档"
xcodebuild \
  -project "$ROOT/TotpScan.xcodeproj" \
  -scheme TotpScan \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

cp "$ROOT/scripts/ExportOptions.plist" "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c "Set :method $METHOD" "$EXPORT_PLIST"

echo "==> 导出 ipa（method=$METHOD）"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates

echo
echo "导出目录：$EXPORT_DIR"
ls -1 "$EXPORT_DIR"
