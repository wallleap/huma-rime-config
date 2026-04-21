-- 1. 根据是否在用户词典，在 comment 上加上一个星号 ✴️
-- 2. 用户置顶词，加上 ✨ 符号
-- 3. 整句联想，加上无穷符号 ♾️
-- 在 engine/filters 增加 - lua_filter@*is_in_user_dict # 是否在用户词典中

local M = {}

-- 统一配置下
local PLUGIN_KEY = "in_user_dict"

-- 配置键名
local CONFIG_KEYS = {
  user_phrase_symbol = "user_phrase_symbol", -- 自定义短语符号配置键
  user_table_symbol = "user_table_symbol", -- 用户词表符号配置键
  sentence_symbol = "sentence_symbol", -- 句子符号配置键
}

-- 默认符号（配置未定义时使用）
local DEFAULT_SYMBOLS = {
  user_phrase = "✴️", -- 自定义短语默认符号
  user_table = "✨", -- 用户词表默认符号
  sentence = "♾️", -- 句子默认符号
}

function M.init(env)
  -- 遍历 CONFIG_KEYS 表，为每个键赋值
  for key, config_key in pairs(CONFIG_KEYS) do
    M[key] = env.engine.schema.config:get_string(PLUGIN_KEY .. "/" .. config_key) or DEFAULT_SYMBOLS[key:gsub("_symbol", "")]
  end
end

function M.func(input)
  for cand in input:iter() do
    local symbol = M[CONFIG_KEYS[cand.type .. "_symbol"]]
    if symbol then
      cand.comment = symbol .. cand.comment
    end

    -- 先拿到原始文本（只读）
    local original_text = cand.text
    
    -- 处理换行符
    if (original_text:match("\\n")) then
      local replaced_text = string.gsub(original_text, "\\n", "\n")

      -- 生成新候选（关键！）
      local new_cand = Candidate(
        cand.type,
        cand.start,
        cand._end,
        replaced_text, -- 你想要的文字
        cand.comment -- 你想要的注释
      )
      
      -- 保留原权重（不影响排序）
      new_cand.quality = cand.quality

      yield(new_cand)
    else
      yield(cand)
    end
  end
end

return M
