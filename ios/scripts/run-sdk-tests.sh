#!/usr/bin/env bash
# 在 macOS 上运行 Swift Package 单元测试。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v swift >/dev/null 2>&1; then
  echo "错误：未找到 swift。请安装 Xcode 或 Swift 工具链。" >&2
  exit 1
fi

swift test --package-path "$ROOT/TotpScanSDK"
