#!/usr/bin/env bash
# lint.sh — Rime 配置仓库格式校验入口
# 用法: bash bin/lint.sh [--strict]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

# 自动安装校验依赖 (仅当缺失时)
if [ ! -d node_modules/js-yaml ] || [ ! -d node_modules/luaparse ]; then
  echo "==> 安装 lint 依赖 (js-yaml, luaparse)..."
  npm install js-yaml@4 luaparse@0.3.1 --no-fund --no-audit --loglevel=error
fi

node "$SCRIPT_DIR/lint.mjs" "$@"
