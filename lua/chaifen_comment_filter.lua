local segment = require("lib.segment")

local function filter(input, env)
  local context = env.engine.context
  local config = env.engine.schema.config
  local seg = context.composition:back()
  if not env.special_tags then segment.init_special_tags(env) end
  local is_reverse = segment.is_reverse_segment(seg)
  local is_special = segment.is_special_segment(seg, env)

  -- 常规输入受 chaifen 开关控制
  local enable = is_reverse or context:get_option("chaifen")
  if not enable or is_special then
    for cand in input:iter() do
      yield(cand)
    end
    return
  end

  -- Initialize OpenCC if not already done in env
  if not env.opencc then
    local opencc_config = config:get_string("chaifen/opencc_config") or "hu_cf.json"
    env.opencc = Opencc(opencc_config)
  end

  local len_config = config:get_int("chaifen/max_char_length")

  for cand in input:iter() do
    -- 超过 max_char_length 字符数的候选不加拆分注释
    local char_len = utf8.len(cand.text) or 0
    if not (len_config and char_len > len_config) then
      local converted = env.opencc:convert_text(cand.text)

      -- If conversion result is different from original text, it means there is a split/comment
      if converted and converted ~= cand.text then
        -- Remove &nbsp; as per original comment_format
        converted = converted:gsub("&nbsp;", " ")
        converted = converted:gsub("〔", "[")
        converted = converted:gsub("〕", ")")
        converted = converted:gsub(" · ", "](")
        -- [字根](编码)

        local current_comment = cand.comment
        if current_comment and current_comment ~= "" then
          -- Append to existing comment
          cand.comment = current_comment .. " " .. converted
        else
          -- Set new comment
          cand.comment = converted
        end
      end
    end
    yield(cand)
  end
end

return filter
