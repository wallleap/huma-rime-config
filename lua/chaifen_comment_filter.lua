local function filter(input, env)
  -- Initialize OpenCC if not already done in env
  if not env.opencc then
    local config = env.engine.schema.config
    local opencc_config = config:get_string("chaifen/opencc_config") or "hu_cf.json"
    env.opencc = Opencc(opencc_config)
  end

  local context = env.engine.context
  -- 通过 segment tag 判断是否为反查，不依赖具体前缀字符
  local seg = context.composition:back()
  local is_reverse = seg and (seg:has_tag("reverse_lookup") or seg:has_tag("flypy_lookup")) or false

  for cand in input:iter() do
    -- 反查时一直显示拆分；常规输入受 chaifen 开关控制
    local enable = is_reverse or context:get_option("chaifen")
    if enable and env.opencc then
      -- Check if the candidate text is longer than max_char_length characters
      local len_config = env.engine.schema.config:get_int("chaifen/max_char_length")
      if len_config and string.len(cand.text) > len_config then
        -- If it is, skip this candidate
      else
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
    end
    yield(cand)
  end
end

return filter
