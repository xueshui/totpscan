#!/usr/bin/env bash
# 一键构建脚本（macOS / Linux）
#
#   ./package.sh            # 构建 SDK（AAR + POM）与 App（APK）
#   ./package.sh sdk        # 只构建 SDK
#   ./package.sh app        # 只构建 App
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"
DIST="$ROOT/dist"

if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" "$HOME/android-studio/jbr"; do
    if [[ -x "$candidate/bin/java" ]]; then JAVA_HOME="$candidate"; break; fi
  done
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "未找到 JDK 17+，请设置 JAVA_HOME" >&2
  exit 1
fi

GRADLE="${GRADLE_CMD:-}"
if [[ -z "$GRADLE" ]]; then
  if command -v gradle >/dev/null 2>&1; then
    GRADLE="$(command -v gradle)"
  else
    echo "未找到 Gradle，请把 gradle 加入 PATH 或设置 GRADLE_CMD" >&2
    exit 1
  fi
fi

TASKS=()
case "$TARGET" in
  all) TASKS+=(":sdk:assembleRelease" ":sdk:publishReleasePublicationToMavenLocal" ":app:assembleRelease" ":app:assembleDebug") ;;
  sdk) TASKS+=(":sdk:assembleRelease" ":sdk:publishReleasePublicationToMavenLocal") ;;
  app) TASKS+=(":app:assembleRelease" ":app:assembleDebug") ;;
  *) echo "用法：$0 [all|sdk|app]" >&2; exit 2 ;;
esac

echo "JAVA_HOME=$JAVA_HOME"
echo "Gradle=$GRADLE"
"$GRADLE" -p "$ROOT" --console=plain "${TASKS[@]}"

mkdir -p "$DIST"
GROUP="com.scanauth"
ARTIFACT="scan-totp-sdk"
VERSION="1.0.0"
while IFS='=' read -r key value; do
  case "$key" in
    scanTotp.group) GROUP="$value" ;;
    scanTotp.artifact) ARTIFACT="$value" ;;
    scanTotp.version) VERSION="$value" ;;
  esac
done < "$ROOT/gradle.properties"

if [[ "$TARGET" == "all" || "$TARGET" == "sdk" ]]; then
  cp "$ROOT/sdk/build/outputs/aar/sdk-release.aar" "$DIST/$ARTIFACT-$VERSION.aar"
  M2="$HOME/.m2/repository/${GROUP//./\/}/$ARTIFACT/$VERSION"
  for name in "$ARTIFACT-$VERSION.pom" "$ARTIFACT-$VERSION-sources.jar" "$ARTIFACT-$VERSION.module"; do
    [[ -f "$M2/$name" ]] && cp "$M2/$name" "$DIST/$name"
  done
fi

if [[ "$TARGET" == "all" || "$TARGET" == "app" ]]; then
  RELEASE_DIR="$ROOT/app/build/outputs/apk/release"

  # 只分发已签名的 Release 包；缺少签名直接失败，不退回未签名或 debug 签名
  if [[ ! -s "$RELEASE_DIR/app-release.apk" ]]; then
    echo "错误：未找到已签名的 Release APK。请先配置 ANDROID_KEYSTORE_* 环境变量或 android/keystore.local.properties。" >&2
    exit 1
  fi
  cp "$RELEASE_DIR/app-release.apk" "$DIST/scan-totp-app-$VERSION-signed.apk"

  for f in "$DIST"/scan-totp-app-"$VERSION"-*.apk; do
    [[ -f "$f" ]] || continue
    if command -v sha256sum >/dev/null 2>&1; then
      echo "SHA256 $(sha256sum "$f" | awk '{print $1}')  $(basename "$f")"
    else
      echo "SHA256 $(shasum -a 256 "$f" | awk '{print $1}')  $(basename "$f")"
    fi
  done
fi

echo "完成。产物目录：$DIST"
ls -1 "$DIST"
