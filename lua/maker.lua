local M = {}
local base = require("lib.base")
local rime_dir = base.get_rime_dir()
local code_map = {}
local dict_loaded = {} -- Map<dict_name, boolean>
local session_words = {} -- Store words added in this session
local user_file_words = {} -- Store words loaded from output file (text -> true)
local user_file_loaded = false

-- Helper to get config
local function get_config(env, key, default)
    if env and env.engine and env.engine.schema and env.engine.schema.config then
        local val = env.engine.schema.config:get_string("maker/" .. key)
        return val or default
    end
    return default
end

-- Helper to get string list config
local function get_string_list(env, key, default_list)
    if env and env.engine and env.engine.schema and env.engine.schema.config then
        local config = env.engine.schema.config
        local list = config:get_list("maker/" .. key)
        if not list then return default_list end
        
        local result = {}
        for i = 0, list.size - 1 do
            local val = list:get_value_at(i)
            if val then
                table.insert(result, val.value)
            end
        end
        return result
    end
    return default_list
end

-- Helper to get output file
local function get_output_file(env)
    if env and env.engine and env.engine.schema and env.engine.schema.config then
        local config = env.engine.schema.config
        
        -- 1. Try maker/output_file
        local val = config:get_string("maker/output_file")
        if val then return val end
        
        -- 2. Try custom_phrase/user_dict
        val = config:get_string("custom_phrase/user_dict")
        if val then return val .. ".txt" end
    end
    
    -- 3. Default
    return "tigress.txt"
end

local function load_dict(dict_name)
    if dict_loaded[dict_name] then return end
    -- Try to read the dictionary file
    -- 1. Try relative path (better for some environments)
    local file_path = "dicts/" .. dict_name .. ".dict.yaml"
    local file, err = io.open(file_path, "r")
    
    -- 2. If failed, try absolute path using rime_dir
    if not file then
        file_path = rime_dir .. "/dicts/" .. dict_name .. ".dict.yaml"
        file, err = io.open(file_path, "r")
    end

    if not file then
        -- Log error if possible (Rime Lua usually provides log global)
        if log and log.error then
            log.error("Maker: Failed to open dictionary: " .. file_path .. ", error: " .. (err or "unknown"))
        end
        return 
    end
    
    for line in file:lines() do
        -- Format: text \t weight \t code
        -- Ignore comments
        if not line:match("^#") and not line:match("^%-%-") then
            -- Trim trailing whitespace (including \r for Windows/DOS format on macOS/Linux)
            line = line:gsub("[\r\n]+$", "")
            local text, weight, code = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
            if text and code then
                -- Trim potential \r from code if match didn't catch it (though gsub above should handle it)
                code = code:gsub("%s+$", "") 
                
                if not code_map[code] then
                    code_map[code] = {}
                end
                -- Avoid duplicates
                local exists = false
                for _, v in ipairs(code_map[code]) do
                    if v == text then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(code_map[code], text)
                end
            end
        end
    end
    file:close()
    dict_loaded[dict_name] = true
end

local function load_user_file(env)
    if user_file_loaded then return end
    local output_file = get_output_file(env)
    local file_path = rime_dir .. "/" .. output_file
    local file = io.open(file_path, "r")
    if file then
        for line in file:lines() do
             -- Format: text \t code \t weight
             local text = line:match("([^\t]+)")
             if text then
                 user_file_words[text] = true
             end
        end
        file:close()
    end
    user_file_loaded = true
end

-- Calculate code based on rules
local function get_code(codes)
    if #codes == 2 then
        -- Rule: AaAb BaBb
        return codes[1]:sub(1,2) .. codes[2]:sub(1,2)
    elseif #codes == 3 then
        -- Rule: Aa Ba CaCb
        return codes[1]:sub(1,1) .. codes[2]:sub(1,1) .. codes[3]:sub(1,2)
    elseif #codes >= 4 then
        -- Rule: Aa Ba Ca Za
        return codes[1]:sub(1,1) .. codes[2]:sub(1,1) .. codes[3]:sub(1,1) .. codes[#codes]:sub(1,1)
    end
    return ""
end

function M.processor(key, env)
    local context = env.engine.context
    local kNoop = 2 
    
    -- Configs
    local separator = get_config(env, "separator", "'")
    local output_file = get_output_file(env)
    local dict_name = get_config(env, "dictionary", "tigress")
    local mark = get_config(env, "candidate_mark", "☯")
    local excluded_prefixes = get_string_list(env, "excluded_prefixes", {"`"})
    
    -- Load dictionary if needed
    if not dict_loaded[dict_name] then load_dict(dict_name) end
    
    local input = context.input
    
    -- Handle separator key (usually ')
    -- We assume separator is a single character.
    -- If key corresponds to separator, allow it.
    -- Safety check: keycode < 256 for ASCII char comparison
    if key.keycode < 256 and string.char(key.keycode) == separator and not key:release() then
        return kNoop -- Allow separator
    end
    
    -- Commit Logic: Check if Space/Enter pressed and we have a maker candidate selected
    if (key.keycode == 32 or key.keycode == 0xff0d) and not key:release() then
        local cand = context:get_selected_candidate()
        if cand and cand.type == "word_maker" then
            -- Parse the comment to get the code
            -- Comment format: " <mark> 造词: code"
            -- We need to match the code part. Since mark is variable, we look for "造词: code" or just last part?
            -- Original regex: ":%s*([a-z]+)"
            -- This should still work if comment is " ☯ 造词: code"
            local code = cand.comment:match(":%s*([a-z]+)")
            if code then
                -- Add to session words (Immediate access)
                if not session_words[code] then
                    session_words[code] = {}
                end
                
                -- Check duplication in session words
                local in_session = false
                for _, w in ipairs(session_words[code]) do
                    if w == cand.text then in_session = true break end
                end
                if not in_session then
                    table.insert(session_words[code], cand.text)
                end
                
                -- Only write to file if not already loaded from file
                if not user_file_words[cand.text] then
                    user_file_words[cand.text] = true

                    -- Target file path
                    local file_path = rime_dir .. "/" .. output_file
                    
                    -- Open file in append mode (creates if not exists)
                    -- Try to ensure file exists first (fix for some mobile envs)
                    local check = io.open(file_path, "r")
                    if not check then
                        local create = io.open(file_path, "w")
                        if create then create:close() end
                    else
                        check:close()
                    end

                    local f = io.open(file_path, "a")
                    if f then
                        f:write(cand.text .. "\t" .. code .. "\t100\n")
                        f:flush()
                        f:close()
                    elseif log and log.error then
                        log.error("Maker: Failed to write to " .. file_path)
                    end
                end
            end
            -- Allow the commit to proceed
            return kNoop
        end
    end
    
    -- Length Limit Logic
    if #input >= 4 then
        -- Check excluded prefixes
        for _, prefix in ipairs(excluded_prefixes) do
            if input:sub(1, #prefix) == prefix then
                return kNoop
            end
        end

        -- If input already has separator, allow
        if input:find(separator, 1, true) then -- use plain find for speed and safety
            return kNoop
        end
        
        -- If valid char (a-z) and no separator in input, Clear previous
        if key.keycode >= 97 and key.keycode <= 122 and not key:release() then
             context:clear()
             return kNoop -- Allow new key to start fresh
        end
    end
    
    return kNoop
end

-- Helper to generate combinations of characters
local function get_combinations(lists, index)
    if index > #lists then return {""} end
    local suffixes = get_combinations(lists, index + 1)
    local result = {}
    for _, char in ipairs(lists[index]) do
        for _, suffix in ipairs(suffixes) do
            table.insert(result, char .. suffix)
        end
    end
    return result
end

function M.translator(input, seg, env)
    -- Configs
    local separator = get_config(env, "separator", "'")
    local dict_name = get_config(env, "dictionary", "tigress")
    local mark = get_config(env, "candidate_mark", "☯")

    local composition = env.engine.context.composition
    local segment = composition:back()

    -- Ensure dict is loaded (in case translator runs first or independently)
    if not dict_loaded[dict_name] then load_dict(dict_name) end
    if not user_file_loaded then load_user_file(env) end

    -- Mode 1: Serve session words (Immediate access)
    -- Also try to match words even if input contains separator (strip it first)
    local clean_input = input:gsub(separator, "") -- Note: if separator has magic chars, gsub might fail.
    -- Better escape separator for pattern matching if needed, or just use plain string replacement?
    -- Lua gsub takes a pattern. 
    -- Safe way to remove separator:
    local escaped_separator = separator:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    clean_input = input:gsub(escaped_separator, "")

    local words = session_words[clean_input]
    if words then
        for _, word in ipairs(words) do
            local cand = Candidate("custom_phrase", seg.start, seg._end, word, "")
            cand.quality = 100
            yield(cand)
        end
    end

    if not input:find(separator, 1, true) then
        return
    end

    segment.prompt = '造词...'

    -- Tag Isolation: prevent filters from modifying comments
    if Set then
        segment.tags = Set({"word_maker"})
    end

    -- Mode 2: Word Maker Logic
    local codes = {}
    -- Split by separator
    for s in input:gmatch("[^" .. escaped_separator .. "]+") do
        table.insert(codes, s)
    end
    
    if #codes < 2 then 
        -- If input has separator but only 1 code segment, show candidates for that segment
        if #codes == 1 and input:find(separator, 1, true) then
            local code = codes[1]
            -- Check dictionary
            local dict_candidates = code_map[code]
            if dict_candidates then
                for _, word in ipairs(dict_candidates) do
                    -- Yield as simple candidates, not word_maker
                    local cand = Candidate("custom_phrase", seg.start, seg._end, word, "")
                    cand.quality = 100
                    yield(cand)
                end
            end
        end
        return 
    end
    
    -- Lookup chars
    local char_lists = {}
    local valid = true
    for _, c in ipairs(codes) do
        local list = code_map[c]
        if not list then
            valid = false
            break 
        end
        table.insert(char_lists, list)
    end
    
    if not valid then return end
    
    local words = get_combinations(char_lists, 1)
    local new_code = get_code(codes)
    
    for _, word in ipairs(words) do
        local exists = user_file_words[word]
        if not exists then
             -- Check session words (iterate)
             for _, list in pairs(session_words) do
                 for _, w in ipairs(list) do
                     if w == word then
                         exists = true
                         break
                     end
                 end
                 if exists then break end
             end
        end

        local comment = " " .. mark .. " 造词: " .. new_code
        if exists then
            comment = " ⚡ 已在词库"
        end

        local cand = Candidate("word_maker", seg.start, seg._end, word, comment)
        cand.quality = 100
        yield(cand)
    end
end

-- Filter to deduplicate user words vs system words
function M.filter(input, env)
    -- Load user file words once
    if not user_file_loaded then load_user_file(env) end

    -- We need to buffer candidates to check for duplicates across types
    local pending = {}
    for cand in input:iter() do
        table.insert(pending, cand)
    end
    
    local seen_texts = {}
    
    for _, cand in ipairs(pending) do
        -- Check if this word is a known user word (from file or current session)
        -- OR if it's explicitly typed as custom_phrase/word_maker
        local is_user_word = user_file_words[cand.text] or 
                             (session_words and next(session_words)) and (function() 
                                 -- Check if text is in any session_words entry? No, session_words is code->list.
                                 -- Easier: just check cand type or simple duplication logic.
                                 return false 
                             end)() or
                             cand.type == "custom_phrase" or 
                             cand.type == "word_maker"

        -- Actually, we can just deduplicate by text. 
        -- If we see the same text twice, we drop the second one.
        -- Assumption: User words (custom_phrase) usually appear first due to high quality.
        -- If system word appears first but matches a user word, we keep it. 
        -- (Wait, if system word matches user word, we might want to ensure it gets marked by is_in_user_dict later. 
        -- Since is_in_user_dict checks the DB, yielding the system word is fine, it will get marked.)
        
        -- Special case: If we have multiple candidates with same text,
        -- we prefer the one that is NOT a generic table type if possible?
        -- But usually custom_phrase IS table type.
        
        if not seen_texts[cand.text] then
            seen_texts[cand.text] = true
            yield(cand)
        else
            -- Duplicate text found.
            -- If the previous one was system and this one is "custom_phrase" (explicit type), 
            -- we might have made a mistake by keeping the system one?
            -- But custom_phrase with initial_quality=100 should come first.
            -- So dropping subsequent duplicates is generally safe.
        end
    end
end

return M
