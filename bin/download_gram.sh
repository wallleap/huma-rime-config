#!/bin/bash
set -euo pipefail

# ===================== 路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "${REPO_ROOT}"

# 临时目录
TMP_DIR="${REPO_ROOT}/.tmp_sync"
mkdir -p "$TMP_DIR"

# ===================== 远程地址 =====================
# FALLBACK_BASE="https://ghfast.top/"
FALLBACK_BASE="https://gh-proxy.com/"

# ===================== 同步列表 =====================
SYNC_LIST=(
  "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram|${REPO_ROOT}"
)

# ===================== 下载函数 =====================
download() {
  local url="$1"
  local out="$2"
  curl -s -f -L "$url" -o "$out"
  return $?
}

# ===================== 主逻辑 =====================
for ITEM in "${SYNC_LIST[@]}"; do
  IFS='|' read -r RAW_URL LOCAL_DIR <<< "$ITEM"
  FILE_NAME=$(basename "$RAW_URL")
  LOCAL_FILE="${LOCAL_DIR}/${FILE_NAME}"
  TMP_FILE="${TMP_DIR}/${FILE_NAME}.tmp"

  echo "========================================"
  echo "检查文件：${FILE_NAME}"
  echo "保存到：${LOCAL_FILE}"

  # 下载
  echo "尝试下载镜像地址... ${FALLBACK_BASE}${RAW_URL}"
  if download "${FALLBACK_BASE}${RAW_URL}" "${TMP_FILE}"; then
    echo "✅ 镜像下载成功"
  else
    echo "⚠️ 镜像下载失败，尝试原始地址... ${RAW_URL}"
    if ! download "${RAW_URL}" "${TMP_FILE}"; then
      echo "❌ 原始地址下载失败，跳过"
      rm -f "${TMP_FILE}"
      continue
    fi
    echo "✅ 原始地址下载成功"
  fi

  rm -f "${LOCAL_FILE}"
  mv "${TMP_FILE}" "${LOCAL_FILE}"
done

# 清理临时文件
rm -rf "${TMP_DIR}"

echo "========================================"
echo "🎉 全部任务完成！"
