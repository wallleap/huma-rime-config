#!/bin/bash
set -euo pipefail

# ===================== 路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "${REPO_ROOT}"

# 临时目录（失败列表也放在这里，结束时不删除以便 --retry）
TMP_DIR="${REPO_ROOT}/.tmp_sync"
mkdir -p "$TMP_DIR"

# 启动清理：只清临时工作目录，保留失败列表
find "${TMP_DIR}" -mindepth 1 -maxdepth 1 \
  \( -name 'job_*' -o -name 'changed_marks' -o -name 'failed_marks' -o -name 'logs' -o -name 'done_marks' \) \
  -exec rm -rf {} + 2>/dev/null || true

# 持久化失败列表（下次 --retry 用）——放在 TMP_DIR 内，结束清理时保留
FAILED_LIST_FILE="${TMP_DIR}/.sync_failed_list"

# ===================== 远程地址 =====================
# FALLBACK_BASE="https://ghfast.top/"
FALLBACK_BASE="https://gh-proxy.com/"

# ===================== 同步列表 =====================
SYNC_LIST=(
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

# ===================== 命令行参数 =====================
RETRY_MODE=0
if [[ "${1:-}" == "--retry" ]]; then
  RETRY_MODE=1
  if [ ! -f "${FAILED_LIST_FILE}" ] || [ ! -s "${FAILED_LIST_FILE}" ]; then
    echo "ℹ️ 没有需要重试的失败记录（${FAILED_LIST_FILE} 为空或不存在）"
    exit 0
  fi
  # 清空原列表，从持久化文件读取
  SYNC_LIST=()
  while IFS= read -r LINE; do
    [ -n "${LINE}" ] && SYNC_LIST+=("${LINE}")
  done < "${FAILED_LIST_FILE}"
  echo "🔁 重试模式：共 ${#SYNC_LIST[@]} 个待重试项"
fi

# ===================== 标记/日志 目录 =====================
CHANGED_MARKS_DIR="${TMP_DIR}/changed_marks"
FAILED_MARKS_DIR="${TMP_DIR}/failed_marks"
LOGS_DIR="${TMP_DIR}/logs"
DONE_MARKS_DIR="${TMP_DIR}/done_marks"
mkdir -p "${CHANGED_MARKS_DIR}" "${FAILED_MARKS_DIR}" "${LOGS_DIR}" "${DONE_MARKS_DIR}"

# ===================== 下载函数 =====================
download() {
  local url="$1"
  local out="$2"
  curl -s -f -L "$url" -o "$out"
  return $?
}

# ===================== 记录失败 =====================
mark_failed() {
  local JOB_ID="$1"
  local ITEM="$2"
  echo "${ITEM}" > "${FAILED_MARKS_DIR}/${JOB_ID}"
}

# ===================== 单个文件处理函数（返回 0 成功，1 失败） =====================
process_item() {
  local ITEM="$1"
  local JOB_ID="$2"

  local JOB_TMP_DIR="${TMP_DIR}/job_${JOB_ID}"
  mkdir -p "${JOB_TMP_DIR}"

  IFS='|' read -r RAW_URL LOCAL_DIR <<< "$ITEM"
  local FILE_NAME
  FILE_NAME=$(basename "$RAW_URL")
  local LOCAL_FILE="${LOCAL_DIR}/${FILE_NAME}"
  local TMP_FILE="${JOB_TMP_DIR}/${FILE_NAME}.tmp"

  echo "========================================"
  echo "[${JOB_ID}] 检查文件：${FILE_NAME}"
  echo "[${JOB_ID}] 保存到：${LOCAL_FILE}"

  # 下载
  echo "[${JOB_ID}] 尝试下载镜像地址... ${FALLBACK_BASE}${RAW_URL}"
  if download "${FALLBACK_BASE}${RAW_URL}" "${TMP_FILE}"; then
    echo "[${JOB_ID}] ✅ 镜像下载成功"
  else
    echo "[${JOB_ID}] ⚠️ 镜像下载失败，尝试原始地址... ${RAW_URL}"
    if ! download "${RAW_URL}" "${TMP_FILE}"; then
      echo "[${JOB_ID}] ❌ 原始地址下载失败，跳过"
      mark_failed "${JOB_ID}" "${ITEM}"
      rm -rf "${JOB_TMP_DIR}"
      return 1
    fi
    echo "[${JOB_ID}] ✅ 原始地址下载成功"
  fi

  # 处理 zi.dict.yaml 文件，在包含 ḿ 和 m̀ 的行前添加 # 空格
  if [ "${FILE_NAME}" = "zi.dict.yaml" ]; then
    echo "[${JOB_ID}] 🔧 处理 zi.dict.yaml 文件..."
    # 创建临时处理文件
    local TMP_PROCESSED="${JOB_TMP_DIR}/${FILE_NAME}.processed"
    # 使用 awk 处理包含 ḿ 或 m̀ 的行
    awk '{if ($0 ~ /ḿ/ || $0 ~ /m̀/) print "# " $0; else print $0}' "${TMP_FILE}" > "${TMP_PROCESSED}"
    # 替换原始临时文件
    mv "${TMP_PROCESSED}" "${TMP_FILE}"
    echo "[${JOB_ID}] ✅ 处理完成"
  fi

  # 本地不存在
  if [ ! -f "${LOCAL_FILE}" ]; then
    echo "[${JOB_ID}] 🆕 创建新文件..."
    mkdir -p "${LOCAL_DIR}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    touch "${CHANGED_MARKS_DIR}/${JOB_ID}"
    rm -rf "${JOB_TMP_DIR}"
    return 0
  fi

  # 对比
  if ! diff -q -b -B "${TMP_FILE}" "${LOCAL_FILE}" >/dev/null 2>&1; then
    echo "[${JOB_ID}] 🔄 文件已更新，替换中..."
    rm -f "${LOCAL_FILE}"
    mv "${TMP_FILE}" "${LOCAL_FILE}"
    touch "${CHANGED_MARKS_DIR}/${JOB_ID}"
  else
    echo "[${JOB_ID}] ✅ 文件无变化"
    rm -f "${TMP_FILE}"
  fi

  rm -rf "${JOB_TMP_DIR}"
  return 0
}

# ===================== 辅助：从 FAILED_MARKS_DIR 收集失败 ITEM 到全局 FAILED_ITEMS =====================
# 使用全局变量兼容 macOS 自带 Bash 3.2（无 nameref 特性）
collect_failed_items() {
  FAILED_ITEMS=()
  if [ -d "${FAILED_MARKS_DIR}" ]; then
    # 用 find + sort 保证顺序稳定
    local f
    while IFS= read -r f; do
      [ -f "$f" ] && FAILED_ITEMS+=("$(cat "$f")")
    done < <(find "${FAILED_MARKS_DIR}" -type f 2>/dev/null | sort)
  fi
}

# ===================== 主逻辑：第一轮 并行下载 =====================
TOTAL_JOBS="${#SYNC_LIST[@]}"
JOB_IDX=0
PIDS=()
for ITEM in "${SYNC_LIST[@]}"; do
  JOB_IDX=$((JOB_IDX + 1))
  # 后台进程的所有输出重定向到独立日志，避免 stdout 交错
  (
    process_item "${ITEM}" "${JOB_IDX}"
    echo "${JOB_IDX}" > "${DONE_MARKS_DIR}/${JOB_IDX}"
  ) > "${LOGS_DIR}/${JOB_IDX}.log" 2>&1 &
  PIDS+=($!)
done

echo "========================================"
echo "🚀 已启动 ${TOTAL_JOBS} 个并行下载任务，等待完成..."
echo ""

# 进度心跳：每隔 1s 统计一次完成数，覆盖式刷新同一行（不穿插详细日志）
show_progress() {
  local done_count
  done_count=$(find "${DONE_MARKS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
  # 进度条：[=====>----------]
  local bar_len=20
  local denom="${TOTAL_JOBS}"
  [ "${denom}" -le 0 ] && denom=1
  local filled=$(( done_count * bar_len / denom ))
  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}="
    i=$((i + 1))
  done
  if [ "$done_count" -lt "$TOTAL_JOBS" ] && [ "$filled" -gt 0 ]; then
    bar="${bar}>"
    i=$((i + 1))
  fi
  while [ "$i" -lt "$bar_len" ]; do
    bar="${bar}-"
    i=$((i + 1))
  done
  printf "\r⏳ [%s] %2d / %d  已完成" "${bar}" "${done_count}" "${TOTAL_JOBS}"
}

while true; do
  show_progress
  # 判断是否全部完成：任一 PID 还活着说明没结束
  ALIVE=0
  for PID in "${PIDS[@]}"; do
    if kill -0 "${PID}" 2>/dev/null; then
      ALIVE=1
      break
    fi
  done
  if [ "${ALIVE}" -eq 0 ]; then
    # 最后收一次 PIDS（避免 defunct 残留）
    for PID in "${PIDS[@]}"; do
      wait "${PID}" || true
    done
    show_progress
    printf "\n"
    break
  fi
  sleep 1
done

echo ""
echo "📋 以下为各任务详细结果（按任务号顺序）："
# 按 JOB_ID 数字顺序打印每个任务的日志，保证输出整齐不交错
LOG_LIST=()
while IFS= read -r f; do
  LOG_LIST+=("$f")
done < <(find "${LOGS_DIR}" -name '*.log' -type f 2>/dev/null | \
  awk -F'/' '{n=$NF; sub(/\.log$/,"",n); print n"\t"$0}' | \
  sort -n -k1 | \
  cut -f2-)
for LOG in "${LOG_LIST[@]}"; do
  cat "${LOG}"
done

# 收集第一轮失败
collect_failed_items

# ===================== 第二轮：自动串行重试一次 =====================
if [ "${#FAILED_ITEMS[@]}" -gt 0 ]; then
  echo "========================================"
  echo "🔁 第一轮有 ${#FAILED_ITEMS[@]} 个任务失败，开始串行重试..."

  # 清空本轮失败标记，重新记录
  rm -f "${FAILED_MARKS_DIR}"/*

  RETRY_IDX=0
  for ITEM in "${FAILED_ITEMS[@]}"; do
    RETRY_IDX=$((RETRY_IDX + 1))
    RETRY_JOB_ID="R${RETRY_IDX}"
    echo "----------------------------------------"
    echo "重试 [${RETRY_JOB_ID}]: ${ITEM}"
    process_item "${ITEM}" "${RETRY_JOB_ID}" || true
  done

  # 再次收集失败
  collect_failed_items
fi

# ===================== 汇总结果 =====================
echo "========================================"
echo "✅ 所有下载任务完成"

# 根据标记文件判断是否有变化
CHANGED=0
if [ -n "$(ls -A "${CHANGED_MARKS_DIR}" 2>/dev/null)" ]; then
  CHANGED=1
fi

# 持久化失败列表（用于下次 --retry）
: > "${FAILED_LIST_FILE}.tmp"
if [ "${#FAILED_ITEMS[@]}" -gt 0 ]; then
  printf '%s\n' "${FAILED_ITEMS[@]}" > "${FAILED_LIST_FILE}.tmp"
  echo "❌ 仍有 ${#FAILED_ITEMS[@]} 个文件下载失败："
  for ITEM in "${FAILED_ITEMS[@]}"; do
    FILE_NAME=$(basename "${ITEM%%|*}")
    echo "   - ${FILE_NAME}"
  done
  echo ""
  echo "💡 下次执行以下命令仅重试失败项："
  echo "   bash ${BASH_SOURCE[0]} --retry"
fi
mv "${FAILED_LIST_FILE}.tmp" "${FAILED_LIST_FILE}"

# 清理临时文件：只清工作子目录，保留失败列表
find "${TMP_DIR}" -mindepth 1 -maxdepth 1 \
  \( -name 'job_*' -o -name 'changed_marks' -o -name 'failed_marks' -o -name 'logs' -o -name 'done_marks' \) \
  -exec rm -rf {} + 2>/dev/null || true

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
if [ "${#FAILED_ITEMS[@]}" -gt 0 ]; then
  echo "⚠️ 存在失败项，请使用 --retry 重试"
  echo "   失败列表保存在：${FAILED_LIST_FILE}"
else
  # 无失败，清理持久化列表
  rm -f "${FAILED_LIST_FILE}"
  # 如果 TMP_DIR 空了，顺手清掉
  if [ -z "$(ls -A "${TMP_DIR}" 2>/dev/null)" ]; then
    rmdir "${TMP_DIR}" 2>/dev/null || true
  fi
  echo "🎉 全部任务完成！"
fi
