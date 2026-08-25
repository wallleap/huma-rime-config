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
  "https://github.com/wallleap/huma-rime-config/releases/download/LTS/sentence-ngram-mobile.bin|${REPO_ROOT}/models"
)

# ===================== Ctrl+C 处理 =====================
# 跟踪当前 curl 子进程的 PID，收到 SIGINT 时只杀掉它，让脚本继续往下走
CURL_PID=""

on_interrupt() {
  if [ -n "${CURL_PID}" ] && kill -0 "${CURL_PID}" 2>/dev/null; then
    kill -INT "${CURL_PID}" 2>/dev/null || true
  fi
}

trap on_interrupt INT

# ===================== 下载函数 =====================
# curl 后台运行并记录 PID，再 wait 它：
# - Ctrl+C 时 trap 只杀当前 curl，wait 返回非 0，函数返回失败
# - 外层用 if 判断，失败就跳到下一个尝试（镜像 → 原始 → 下一个链接）
download() {
  local url="$1"
  local out="$2"
  curl -s -f -L "$url" -o "$out" &
  CURL_PID=$!
  local code=0
  wait "$CURL_PID" || code=$?
  CURL_PID=""
  return $code
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

  # 1) 先尝试镜像地址
  echo "尝试下载镜像地址... ${FALLBACK_BASE}${RAW_URL}"
  if download "${FALLBACK_BASE}${RAW_URL}" "${TMP_FILE}"; then
    echo "✅ 镜像下载成功"
    rm -f "${LOCAL_FILE}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    continue
  fi

  # 2) 镜像失败或被 Ctrl+C 中断，回退原始地址
  echo "⚠️ 镜像下载失败或被中断，尝试原始地址... ${RAW_URL}"
  if download "${RAW_URL}" "${TMP_FILE}"; then
    echo "✅ 原始地址下载成功"
    rm -f "${LOCAL_FILE}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    continue
  fi

  # 3) 原始地址也失败或被中断，跳过当前文件进入下一个链接
  echo "❌ 原始地址下载失败或被中断，跳过该文件"
  rm -f "${TMP_FILE}"
done

# 清理临时文件
rm -rf "${TMP_DIR}"

echo "========================================"
echo "🎉 全部任务完成！"
