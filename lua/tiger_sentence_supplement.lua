-- Per-schema supplemental phrase rewards for TigerClaw sentence decoding.
local M = {}

local file_name = "tiger_sentence.supplement.txt"
local baseline_reward = 9.0
local weight_scale = 2.0
local baseline_weight = 1000.0
local maximum_reward = 16.0

local function utf_chars(text)
    local chars = {}
    local index = 1
    while index <= #text do
        local first = text:byte(index)
        local length = first < 0x80 and 1 or first < 0xE0 and 2 or first < 0xF0 and 3 or 4
        chars[#chars + 1] = text:sub(index, index + length - 1)
        index = index + length
    end
    return chars
end

local function reward_for_weight(weight)
    local bounded = math.max(1, math.min(1000000000, weight))
    local reward = baseline_reward + weight_scale * math.log(bounded / baseline_weight)
    return math.max(0.0, math.min(maximum_reward, reward))
end

local function empty_matcher(path, load_error)
    return {
        nodes = { { transitions = {}, failure = 1, reward = 0.0 } },
        path = path,
        count = 0,
        error = load_error
    }
end

function M.build(entries, path)
    local nodes = { { transitions = {}, failure = 1, reward = 0.0 } }
    local count = 0
    for text, weight in pairs(entries or {}) do
        local reward = reward_for_weight(weight)
        if text ~= "" and reward > 0.0 then
            local state = 1
            local chars = utf_chars(text)
            for i = 1, #chars do
                local next_state = nodes[state].transitions[chars[i]]
                if not next_state then
                    next_state = #nodes + 1
                    nodes[state].transitions[chars[i]] = next_state
                    nodes[next_state] = { transitions = {}, failure = 1, reward = 0.0 }
                end
                state = next_state
            end
            nodes[state].reward = math.max(nodes[state].reward, reward)
            count = count + 1
        end
    end

    if count == 0 then
        return empty_matcher(path, nil)
    end

    local queue = {}
    local head = 1
    for _, child in pairs(nodes[1].transitions) do
        nodes[child].failure = 1
        queue[#queue + 1] = child
    end
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for ch, child in pairs(nodes[current].transitions) do
            local fallback = nodes[current].failure
            while fallback ~= 1 and not nodes[fallback].transitions[ch] do
                fallback = nodes[fallback].failure
            end
            local failure_target = nodes[fallback].transitions[ch]
            if failure_target and failure_target ~= child then
                nodes[child].failure = failure_target
            else
                nodes[child].failure = 1
            end
            nodes[child].reward = math.max(
                nodes[child].reward,
                nodes[nodes[child].failure].reward)
            queue[#queue + 1] = child
        end
    end
    return { nodes = nodes, path = path, count = count, error = nil }
end

function M.load_file(path)
    local handle, open_error = io.open(path, "rb")
    if not handle then
        return empty_matcher(path, open_error)
    end
    local content = handle:read("*a") or ""
    handle:close()
    content = content:gsub("^\239\187\191", "")

    local entries = {}
    for raw_line in (content .. "\n"):gmatch("(.-)\r?\n") do
        local line = raw_line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local text, rest = line:match("^(%S+)%s*(.-)$")
            local weight = 1000
            if rest and rest ~= "" then
                if not rest:match("^%d+$") then
                    text = nil
                else
                    weight = tonumber(rest)
                    if not weight or weight <= 0 then text = nil end
                end
            end
            if text then entries[text] = weight end
        end
    end
    return M.build(entries, path)
end

local function join_path(directory, name)
    if directory:sub(-1) == "/" or directory:sub(-1) == "\\" then
        return directory .. name
    end
    return directory .. "/" .. name
end

function M.default_path()
    if not rime_api or type(rime_api.get_user_data_dir) ~= "function" then
        return nil
    end
    local ok, directory = pcall(rime_api.get_user_data_dir)
    if not ok or type(directory) ~= "string" or directory == "" then
        return nil
    end
    return join_path(directory, file_name)
end

function M.load_default()
    local path = M.default_path()
    if not path then return empty_matcher(nil, nil) end
    local matcher = M.load_file(path)
    -- A missing optional file is normal; only report malformed/unreadable files
    -- after the path has actually resolved in a Rime frontend.
    return matcher
end

function M.advance(matcher, state, ch)
    if not matcher or matcher.count == 0 or not ch or ch == "" then
        return 1, 0.0
    end
    local nodes = matcher.nodes
    local current = type(state) == "number" and nodes[state] and state or 1
    while current ~= 1 and not nodes[current].transitions[ch] do
        current = nodes[current].failure
    end
    current = nodes[current].transitions[ch] or 1
    return current, nodes[current].reward
end

M.file_name = file_name
M.reward_for_weight = reward_for_weight
return M
