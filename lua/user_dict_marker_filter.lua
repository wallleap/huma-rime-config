-- user_dict_marker_filter.lua
-- 1. 用户词典候选（自定义短语/用户词表/整句联想）在 comment 前加符号标记
-- 2. 候选文本中的字面 \n 展开为换行符
-- 用法：engine/filters 增加 - lua_filter@*user_dict_marker_filter

local M = {}

local PLUGIN_KEY = "user_dict_marker"

local SYMBOL_TYPES = { "user_phrase", "user_table", "sentence" }

local DEFAULT_SYMBOLS = {
  user_phrase = "✴️", -- 自定义短语默认符号
  user_table = "✨",   -- 用户词表默认符号
  sentence = "♾️",     -- 句子默认符号
}

local symbols

local function load_symbols(env)
  local config = env.engine.schema.config
  local syms = {}
  for i = 1, #SYMBOL_TYPES do
    local t = SYMBOL_TYPES[i]
    syms[t] = config:get_string(PLUGIN_KEY .. "/" .. t .. "_symbol") or DEFAULT_SYMBOLS[t]
  end
  return syms
end

function M.init(env)
  symbols = load_symbols(env)
end

function M.func(input, env)
  local syms = symbols or (env and load_symbols(env)) or DEFAULT_SYMBOLS

  for cand in input:iter() do
    local symbol = syms[cand.type]
    if symbol then
      cand.comment = symbol .. (cand.comment or "")
    end

    -- 字面 \n 展开为换行符；文本未变则直接透传
    local original_text = cand.text
    local replaced_text = string.gsub(original_text, "\\n", "\n")
    if replaced_text ~= original_text then
      local new_cand = Candidate(cand.type, cand.start, cand._end, replaced_text, cand.comment)
      new_cand.quality = cand.quality
      yield(new_cand)
    else
      yield(cand)
    end
  end
end

return M
