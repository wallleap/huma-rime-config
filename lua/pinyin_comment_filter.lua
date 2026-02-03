local function filter(input, env)
    -- Initialize OpenCC if not already done in env
    if not env.opencc then
        local config = env.engine.schema.config
        local opencc_config = config:get_string("pinyin/opencc_config") or "pinyin.json"
        env.opencc = Opencc(opencc_config)
    end
    
    local context = env.engine.context
    
    for cand in input:iter() do
        -- Check switch state for every candidate
        -- Using the switch name "pinyin" as defined in schema
        if context:get_option("pinyin") and env.opencc then
            local converted = env.opencc:convert_text(cand.text)
            
            -- If conversion result is different from original text, it means there is a split/comment
            if converted and converted ~= cand.text then
                -- Remove &nbsp; as per original comment_format
                converted = converted:gsub("&nbsp;", " ")
                
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