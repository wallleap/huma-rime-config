local M = {}
local code_map = {}
local dict_loaded = false
local session_words = {} -- Store words added in this session

local function load_dict()
    if dict_loaded then return end
    -- Try to read the dictionary file
    local file = io.open("f:/Configs/Rime/dicts/tigress.dict.yaml", "r")
    if not file then return end
    
    for line in file:lines() do
        -- Format: text \t weight \t code
        -- Ignore comments
        if not line:match("^#") and not line:match("^%-%-") then
            local text, weight, code = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
            if text and code then
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
    dict_loaded = true
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
    
    kNoop = 2
    
    -- Load dictionary if needed
    if not dict_loaded then load_dict() end
    
    local input = context.input
    
    -- Handle ' key (39)
    if key.keycode == 39 and not key:release() then
        return kNoop -- Allow '
    end
    
    -- Commit Logic: Check if Space/Enter pressed and we have a maker candidate selected
    if (key.keycode == 32 or key.keycode == 0xff0d) and not key:release() then
        local cand = context:get_selected_candidate()
        if cand and cand.type == "word_maker" then
            -- Parse the comment to get the code
            -- Comment format: "☯ 造词: code"
            -- Extract only the alphabetic code
            local code = cand.comment:match(":%s*([a-z]+)")
            if code then
                -- Add to session words (Immediate access)
                if not session_words[code] then
                    session_words[code] = {}
                end
                table.insert(session_words[code], cand.text)

                -- Target file path
                local file_path = "f:/Configs/Rime/tigress.txt"
                
                -- Open file in append mode (creates if not exists)
                local f = io.open(file_path, "a")
                if f then
                    f:write(cand.text .. "\t" .. code .. "\t100\n")
                    f:close()
                end
            end
            -- Allow the commit to proceed
            return kNoop
        end
    end
    
    -- Length Limit Logic
    if #input >= 4 then
        -- If input already has ', allow
        if input:find("'") then
            return kNoop
        end
        
        -- If valid char (a-z) and no ' in input, Clear previous
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
    -- Mode 1: Serve session words (Immediate access)
    if not input:find("'") then
        local words = session_words[input]
        if words then
            for _, word in ipairs(words) do
                local cand = Candidate("custom_phrase", seg.start, seg._end, word, "")
                cand.quality = 100
                yield(cand)
            end
        end
        return
    end

    -- Mode 2: Word Maker Logic
    local codes = {}
    for s in input:gmatch("[^']+") do
        table.insert(codes, s)
    end
    
    if #codes < 2 then return end
    
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
        local cand = Candidate("word_maker", seg.start, seg._end, word, " ☯ 造词: " .. new_code)
        cand.quality = 100
        yield(cand)
    end
end

return M
