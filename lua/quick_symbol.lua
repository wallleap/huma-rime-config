-- quick_symbol.lua
-- 虎码整句方案快捷符号直上屏脚本
-- rime.lua 中导入
-- quick_symbol_processor = require("quick_symbol")
-- schema 中使用
-- engine/processors/+: lua_processor@quick_symbol_processor # 快捷符号直上屏（分号+按键），需在 tiger_sentence_processor 之前拦截

local quick_map = {
  -- 特殊快符：双击分号 & 分号加空格
  [";;"] = "；",
  ["; "] = "：",

  -- 第一排
  [";q"] = "：“",
  [";w"] = "？",
  [";e"] = "（",
  [";r"] = "）",
  [";t"] = "→",
  [";y"] = "·",
  [";u"] = "~",
  [";i"] = "——",
  [";o"] = "〖",
  [";p"] = "〗",

  -- 第二排
  [";a"] = "！",
  [";s"] = "……",
  [";d"] = "、",
  [";f"] = "“",
  [";g"] = "”",
  [";h"] = "『",
  [";j"] = "』",
  [";k"] = "￥",
  [";l"] = "%",

  -- 第三排
  [";z"] = "|",
  [";x"] = "【",
  [";c"] = "】",
  [";v"] = "《",
  [";b"] = "》",
  [";n"] = "「",
  [";m"] = "」",
}

local function processor(key_event, env)
  -- 忽略释放按键及快捷组合键
  if key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps() then
    return 2 -- kNoop
  end

  local context = env.engine.context
  local inp = context.input

  -- 仅在当前缓冲区仅有分号 ";" 时拦截处理后续按键
  if inp == ";" then
    local repr = key_event:repr()
    
    -- 将按键转为匹配字符串：空格转为空格字符 " "，分号转为 ";"
    local key_char = ""
    if repr == "space" then
      key_char = " "
    elseif repr == "semicolon" or repr == ";" then
      key_char = ";"
    else
      key_char = repr
    end

    local new_inp = ";" .. key_char
    local target_text = quick_map[new_inp]

    if target_text then
      env.engine:commit_text(target_text)
      context:clear()
      return 1 -- kAccepted（消费按键并直接上屏目标符号）
    end
  end

  return 2 -- kNoop
end

return processor