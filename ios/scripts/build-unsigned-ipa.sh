#!/usr/bin/env bash
# 构建未签名的 .ipa（Payload/TotpScan.app）。
# 适用于 TrollStore 等可直接安装未签名包的场景，或作为后续自签名的输入。
# 未签名包不能直接安装到普通非越狱设备。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：未找到 xcodebuild。请在 macOS + Xcode 环境中运行此脚本。" >&2
  exit 1
fi

BUILD_DIR="$ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/TotpScan.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$BUILD_DIR/TotpScan-unsigned.ipa"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 编译（关闭代码签名）"
xcodebuild \
  -project "$ROOT/TotpScan.xcodeproj" \
  -scheme TotpScan \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "错误：未找到构建产物 $APP_PATH" >&2
  exit 1
fi

echo "==> 打包 Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"
rm -rf "$PAYLOAD_DIR/TotpScan.app/_CodeSignature"

(
  cd "$BUILD_DIR"
  rm -f "$IPA_PATH"
  zip -qry "$IPA_PATH" Payload
)

echo
echo "已生成：$IPA_PATH"
echo "SHA-256：$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
echo
echo "说明：该包未签名。普通非越狱设备无法直接安装，需要 TrollStore 或使用自己的证书重签。"
