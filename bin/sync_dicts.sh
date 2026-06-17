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
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/PY_c.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/core2022.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/easy_english.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/master/tiger.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress_ci.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress_simp_ci.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/cuoyin.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/diming.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/duoyin.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/jichu.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/lianxiang.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/renming.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/shici.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/wuzhong.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/zi.dict.yaml|${REPO_ROOT}/dicts"
)

# ===================== 下载函数 =====================
download() {
  local url="$1"
  local out="$2"
  curl -s -f -L "$url" -o "$out"
  return $?
}

# ===================== 主逻辑 =====================
CHANGED=0

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

  # 处理 zi.dict.yaml 文件，在包含 ḿ 和 m̀ 的行前添加 # 空格
  if [ "${FILE_NAME}" = "zi.dict.yaml" ]; then
    echo "🔧 处理 zi.dict.yaml 文件..."
    # 创建临时处理文件
    TMP_PROCESSED="${TMP_DIR}/${FILE_NAME}.processed"
    # 使用 awk 处理包含 ḿ 或 m̀ 的行
    awk '{if ($0 ~ /ḿ/ || $0 ~ /m̀/) print "# " $0; else print $0}' "${TMP_FILE}" > "${TMP_PROCESSED}"
    # 替换原始临时文件
    mv "${TMP_PROCESSED}" "${TMP_FILE}"
    echo "✅ 处理完成"
  fi

  # 本地不存在
  if [ ! -f "${LOCAL_FILE}" ]; then
    echo "🆕 创建新文件..."
    mkdir -p "${LOCAL_DIR}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    CHANGED=1
    continue
  fi

  # 对比
  if ! diff -q -b -B "${TMP_FILE}" "${LOCAL_FILE}" >/dev/null 2>&1; then
    echo "🔄 文件已更新，替换中..."
    rm -f "${LOCAL_FILE}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    CHANGED=1
  else
    echo "✅ 文件无变化"
    rm -f "${TMP_FILE}"
  fi
done

# 清理临时文件
rm -rf "${TMP_DIR}"

# ===================== Git 自动提交推送 =====================
echo "========================================"
if [ "${CHANGED}" -eq 1 ]; then
  echo "📤 检测到文件变化，开始提交 Git..."
  git add dicts/
  git commit -m "chore(dicts): 更新字典文件 $(date '+%Y-%m-%d %H:%M:%S')"
  git push
  echo "✅ Git 推送完成！"
else
  echo "✅ 无文件变化，跳过 Git 提交"
fi

echo "========================================"
echo "🎉 全部任务完成！"
