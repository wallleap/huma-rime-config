#!/bin/bash
set -euo pipefail

# 从 dicts/core2022.dict.yaml 生成 Lua 字集白名单表
# 产出：lua/data/core2022/data.lua，供 lua/core2022_filter.lua 过滤非常用字
# 词典格式：每行 `字<Tab>编码`；YAML 头与 `...` 分隔行无 Tab，自动跳过

# ===================== 路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "${REPO_ROOT}"

DICT_FILE="${REPO_ROOT}/dicts/core2022.dict.yaml"
OUT_DIR="${REPO_ROOT}/lua/data/core2022"
OUT_FILE="${OUT_DIR}/data.lua"

if [ ! -f "${DICT_FILE}" ]; then
  echo "❌ 找不到字集词典：${DICT_FILE}"
  exit 1
fi

mkdir -p "${OUT_DIR}"

# awk 按_tab_分隔：NF>=2 表示词条行（有编码列），首列即字
# header（name/version/...）无 Tab，NF==1 自动跳过
echo "🔧 生成 ${OUT_FILE}"
awk -F'\t' '
  BEGIN {
    print "-- 自动生成，请勿手动修改"
    print "-- 由 bin/gen_core2022.sh 从 dicts/core2022.dict.yaml 生成"
    print "-- 用途：core2022 字集过滤的常用字白名单"
    print "return {"
  }
  NF >= 2 && $1 !~ /^[[:space:]]*#/ {
    printf "  [\"%s\"]=true,\n", $1
  }
  END { print "}" }
' "${DICT_FILE}" > "${OUT_FILE}.tmp"

COUNT=$(awk -F'\t' 'NF >= 2 && $1 !~ /^[[:space:]]*#/' "${DICT_FILE}" | wc -l | tr -d ' ')
mv -f "${OUT_FILE}.tmp" "${OUT_FILE}"
echo "✅ 生成完成，共 ${COUNT} 个字 → ${OUT_FILE}"
