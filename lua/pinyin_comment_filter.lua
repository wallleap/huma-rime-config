local function filter(input, env)
  local context = env.engine.context
  local config = env.engine.schema.config
  -- 通过 segment tag 判断是否为反查，不依赖具体前缀字符
  local seg = context.composition:back()
  local is_reverse = seg and (seg:has_tag("reverse_lookup") or seg:has_tag("flypy_lookup")) or false
  -- switcher（mode）切换方案的候选不追加注释
  local switcher_tag = config:get_string("switcher/tag") or "mode"
  local is_switcher = seg and seg:has_tag(switcher_tag) or false

  -- 反查时一直显示拼音；常规输入受 pinyin 开关控制
  local enable = is_reverse or context:get_option("pinyin")
  if not enable or is_switcher then
    for cand in input:iter() do
      yield(cand)
    end
    return
  end

  -- Initialize OpenCC if not already done in env
  if not env.opencc then
    local opencc_config = config:get_string("pinyin/opencc_config") or "pinyin.json"
    env.opencc = Opencc(opencc_config)
  end

  for cand in input:iter() do
    local converted = env.opencc:convert_text(cand.text)

    -- If conversion result is different from original text, it means there is a split/comment
    if converted and converted ~= cand.text then
      -- Remove &nbsp; as per original comment_format
      converted = converted:gsub("&nbsp;", " ")
      converted = converted:gsub("（", "(")
      converted = converted:gsub("）", ")")

      local current_comment = cand.comment
      if current_comment and current_comment ~= "" then
        -- Append to existing comment
        cand.comment = current_comment .. " " .. converted
      else
        -- Set new comment
        cand.comment = converted
      end
    end
    yield(cand)
  end
end

return filter
