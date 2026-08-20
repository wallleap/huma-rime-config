local segment = require("lib.segment")

local function filter(input, env)
  local context = env.engine.context
  local config = env.engine.schema.config
  local seg = context.composition:back()
  if not env.special_tags then segment.init_special_tags(env) end
  local is_reverse = segment.is_reverse_segment(seg)
  local is_special = segment.is_special_segment(seg, env)

  -- 常规输入受 pinyin 开关控制
  local enable = is_reverse or context:get_option("pinyin")
  if not enable or is_special then
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
