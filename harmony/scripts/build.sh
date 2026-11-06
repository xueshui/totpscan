#!/usr/bin/env bash
# 一键构建：hvigorw assembleHap
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TASK="${1:-assembleHap}"
MODULE="${2:-entry}"
PRODUCT="${3:-default}"

echo "==> 项目目录: $ROOT"
echo "==> 构建任务: $TASK (module=$MODULE, product=$PRODUCT)"

HVIGOR=""

if [[ -n "${HVIGOR_PATH:-}" && -x "${HVIGOR_PATH}" ]]; then
  HVIGOR="${HVIGOR_PATH}"
fi

if [[ -z "$HVIGOR" ]]; then
  CANDIDATES=(
    "${DEVECO_HOME:-}/tools/hvigor/bin/hvigorw"
    "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"
    "$HOME/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"
    "/opt/huawei/DevEco-Studio/tools/hvigor/bin/hvigorw"
  )
  for item in "${CANDIDATES[@]}"; do
    if [[ -n "$item" && -x "$item" ]]; then
      HVIGOR="$item"
      break
    fi
  done
fi

if [[ -z "$HVIGOR" && -f "$ROOT/hvigor/hvigor-wrapper.js" ]]; then
  echo "==> 使用项目内 hvigor wrapper"
  exec node "$ROOT/hvigor/hvigor-wrapper.js" "$TASK" \
    --mode module -p "product=$PRODUCT" -p "module=$MODULE@default" --no-daemon
fi

if [[ -z "$HVIGOR" ]]; then
  FOUND="$(command -v hvigorw || true)"
  if [[ -n "$FOUND" && "$FOUND" != "$ROOT/hvigorw" ]]; then
    HVIGOR="$FOUND"
  fi
fi

if [[ -z "$HVIGOR" ]]; then
  cat <<'EOF'

未找到 hvigor 构建工具。

本机没有检测到 DevEco Studio 自带的 hvigor，也没有项目内的 hvigor wrapper。
这通常意味着当前机器未安装 DevEco Studio，因此无法在本机实际编译 HAP。

可选做法：
  1. 安装 DevEco Studio 5.0（API 12）后，用 DevEco 打开 harmony 目录并等待 Sync 完成；
     本脚本会自动发现 DevEco 自带的 hvigor。
  2. 或显式传入路径：
     HVIGOR_PATH=/path/to/hvigorw bash scripts/build.sh
  3. 或把 DevEco 生成的 hvigorw / hvigorw.bat / hvigor/hvigor-wrapper.js 放回项目根目录，
     再执行 hvigorw assembleHap。

源码与工程结构已完整交付，缺少的只是本机的鸿蒙构建工具链。
EOF
  exit 1
fi

echo "==> 使用 hvigor: $HVIGOR"
exec "$HVIGOR" "$TASK" --mode module -p "product=$PRODUCT" -p "module=$MODULE@default" --no-daemon
