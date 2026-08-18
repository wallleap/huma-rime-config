-- TigerClaw-style sentence lattice for Rime, with optional Lua KN scoring.
local lexicon = require("tiger_sentence_lexicon")
local kn_reader = require("tiger_sentence_kn")
local ranks = require("tiger_sentence_ranks")

local beam_width = 200
local candidate_limit = 20
local isolation_threshold = 3000
local isolation_lambda = 2.0
local BOS = kn_reader.BOS
local EOS = kn_reader.EOS
local kn_model = false
local max_code_len = 1
for i = 1, #lexicon.lengths do
    if lexicon.lengths[i] > max_code_len then
        max_code_len = lexicon.lengths[i]
    end
end

local logp_cache = {}
local decode_cache = {
    raw = nil,
    states = nil,
    result = nil
}

local function ensure_kn()
    if kn_model ~= false then
        return kn_model
    end
    kn_model = kn_reader.try_load() or nil
    return kn_model
end

local function logp(prev2, prev1, target)
    local key = prev2 .. "\0" .. prev1 .. "\0" .. target
    local cached = logp_cache[key]
    if cached then
        return cached
    end
    local model = ensure_kn()
    local value = 0
    if model then
        value = model.logp(prev2, prev1, target)
    end
    logp_cache[key] = value
    return value
end

local function trailing_selector_span(raw)
    local index = #raw
    while index >= 1 do
        local mark = raw:sub(index, index)
        if mark:match("%d") or mark == ";" or mark == "'" then
            index = index - 1
        else
            break
        end
    end
    return #raw - index
end

local function normalize(raw)
    if not raw then
        return ""
    end
    return raw:lower():gsub("%s+", "")
end

local function has_letter(raw)
    return raw:find("%a") ~= nil
end

local function utf_chars(text)
    local chars = {}
    if utf8 and utf8.codes then
        for _, codepoint in utf8.codes(text) do
            chars[#chars + 1] = utf8.char(codepoint)
        end
        return chars
    end
    chars[1] = text
    return chars
end

local function isolation_penalty(text)
    local model = ensure_kn()
    if not model or not model.has_observed_bigram or not text or text == "" then
        return 0
    end
    local chars = utf_chars(text)
    local penalty = 0
    for index = 1, #chars do
        local rank = ranks.rank(chars[index])
        if rank > isolation_threshold then
            local left_hit = index > 1 and model.has_observed_bigram(chars[index - 1], chars[index])
            local right_hit = index < #chars and model.has_observed_bigram(chars[index], chars[index + 1])
            if not left_hit and not right_hit then
                penalty = penalty + isolation_lambda
            end
        end
    end
    return penalty
end

local function parse_selector(raw, code_end)
    local next_index = code_end + 1
    if next_index > #raw then
        return 0, code_end
    end
    local mark = raw:sub(next_index, next_index)
    if mark == ";" then
        return 2, next_index
    end
    if mark == "'" then
        return 3, next_index
    end
    if mark:match("%d") then
        local digit_end = next_index
        while digit_end < #raw and raw:sub(digit_end + 1, digit_end + 1):match("%d") do
            digit_end = digit_end + 1
        end
        local token = raw:sub(next_index, digit_end)
        if token == "0" then
            return 10, digit_end
        end
        return tonumber(token) or 0, digit_end
    end
    return 0, code_end
end

local function dedup_limit(states, limit)
    if not states or #states == 0 then
        return {}
    end
    local best = {}
    local order = {}
    for i = 1, #states do
        local item = states[i]
        local previous = best[item.text]
        if not previous then
            order[#order + 1] = item.text
            best[item.text] = item
        elseif item.score > previous.score then
            best[item.text] = item
        end
    end
    local result = {}
    for i = 1, #order do
        result[#result + 1] = best[order[i]]
    end
    table.sort(result, function(left, right)
        return left.score > right.score
    end)
    if #result > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = result[i]
        end
        return trimmed
    end
    return result
end

local function new_states(length)
    local states = {}
    for index = 0, length do
        states[index] = {}
    end
    states[0][1] = { score = 0, text = "", segmented = "", prev2 = BOS, prev1 = BOS }
    return states
end

local function expand_range(raw, states, from_pos, length)
    for position = from_pos, length - 1 do
        local current = dedup_limit(states[position], beam_width)
        states[position] = current
        if #current > 0 then
            for i = 1, #lexicon.lengths do
                local code_length = lexicon.lengths[i]
                if position + code_length <= length then
                    local code = raw:sub(position + 1, position + code_length)
                    local candidates = lexicon.codes[code]
                    if candidates then
                        local selected_rank, consumed_end = parse_selector(raw, position + code_length)
                        if not (length > 1 and consumed_end - position < 2) then
                            local required_rank = selected_rank > 0 and selected_rank or 1
                            for c = 1, #current do
                                local item = current[c]
                                for k = 1, #candidates do
                                    local candidate = candidates[k]
                                    if candidate.r == required_rank then
                                        local score = item.score
                                        local prev2, prev1 = item.prev2, item.prev1
                                        local chars = utf_chars(candidate.t)
                                        for ci = 1, #chars do
                                            score = score + logp(prev2, prev1, chars[ci])
                                            prev2 = prev1
                                            prev1 = chars[ci]
                                        end
                                        local piece = raw:sub(position + 1, consumed_end)
                                        local segmented = item.segmented
                                        if segmented == "" then
                                            segmented = piece
                                        else
                                            segmented = segmented .. " " .. piece
                                        end
                                        local next_states = states[consumed_end]
                                        next_states[#next_states + 1] = {
                                            score = score,
                                            text = item.text .. candidate.t,
                                            segmented = segmented,
                                            prev2 = prev2,
                                            prev1 = prev1
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function emit(states, length)
    local completed = dedup_limit(states[length], beam_width)
    local result = {}
    for i = 1, #completed do
        local item = completed[i]
        result[i] = {
            score = item.score + logp(item.prev2, item.prev1, EOS) - isolation_penalty(item.text),
            text = item.text,
            segmented = item.segmented,
            prev2 = item.prev2,
            prev1 = item.prev1
        }
    end
    table.sort(result, function(left, right)
        if left.score == right.score then
            return left.text < right.text
        end
        return left.score > right.score
    end)
    if #result > candidate_limit then
        local trimmed = {}
        for i = 1, candidate_limit do
            trimmed[i] = result[i]
        end
        return trimmed
    end
    return result
end

local function results_equal(left, right)
    if #left ~= #right then
        return false
    end
    for i = 1, #left do
        if left[i].text ~= right[i].text
            or left[i].segmented ~= right[i].segmented
            or left[i].score ~= right[i].score then
            return false
        end
    end
    return true
end

local function decode_full(raw_code)
    local raw = normalize(raw_code)
    if raw == "" or not has_letter(raw) then
        return {}
    end
    local length = #raw
    local states = new_states(length)
    expand_range(raw, states, 0, length)
    return emit(states, length)
end

local function decode(raw_code)
    local raw = normalize(raw_code)
    if raw == "" or not has_letter(raw) then
        decode_cache.raw = raw
        decode_cache.states = nil
        decode_cache.result = {}
        return decode_cache.result
    end
    if decode_cache.raw == raw and decode_cache.result then
        return decode_cache.result
    end

    local length = #raw
    local states = nil
    local old_raw = decode_cache.raw
    local old_states = decode_cache.states
    if old_states and type(old_raw) == "string" and old_raw ~= "" then
        local old_n = #old_raw
        -- A one-key segment is legal only when the whole input is one key.
        -- Crossing that boundary changes which edges exist at position 1.
        if old_n == 1 or length == 1 then
            states = nil
        elseif length > old_n and raw:sub(1, old_n) == old_raw then
            local max_consume = max_code_len + trailing_selector_span(raw)
            local from_pos = math.max(0, old_n + 1 - max_consume)
            states = old_states
            for index = old_n + 1, length do
                states[index] = {}
            end
            expand_range(raw, states, from_pos, length)
        elseif length < old_n and old_raw:sub(1, length) == raw then
            states = old_states
            for index = length + 1, old_n do
                states[index] = nil
            end
        end
    end

    if not states then
        states = new_states(length)
        expand_range(raw, states, 0, length)
    end

    local result = emit(states, length)
    decode_cache.raw = raw
    decode_cache.states = states
    decode_cache.result = result
    return result
end

local function reset_decode_cache()
    decode_cache.raw = nil
    decode_cache.states = nil
    decode_cache.result = nil
end

local function is_plain_char_key(key_event, repr)
    if key_event:ctrl() or key_event:alt() or key_event:super() then
        return nil
    end
    if #repr == 1 and repr:match("[a-z]") then
        return repr
    end
    if repr == "semicolon" then
        return ";"
    end
    if repr == "apostrophe" then
        return "'"
    end
    if repr:match("^[0-9]$") then
        return repr
    end
    local kp = repr:match("^KP_([0-9])$")
    if kp then
        return kp
    end
    return nil
end

local function processor(key_event, env)
    if key_event:release() then
        return 2
    end
    local context = env.engine.context
    local repr = key_event:repr()
    local ch = is_plain_char_key(key_event, repr)
    if ch then
        -- Digits are rank suffixes only while composing. Idle Chinese mode
        -- should commit 0-9 like a normal Rime schema (including 全角).
        if ch:match("%d") and not context:is_composing() then
            if #repr == 1 then
                return 2
            end
            if context:get_option("full_shape") then
                local full = { "０", "１", "２", "３", "４", "５", "６", "７", "８", "９" }
                env.engine:commit_text(full[tonumber(ch) + 1])
            else
                env.engine:commit_text(ch)
            end
            return 1
        end
        context:push_input(ch)
        return 1
    end
    if not context:is_composing() then
        return 2
    end
    if repr == "Return" or repr == "KP_Enter" then
        env.engine:commit_text(context.input)
        context:clear()
        return 1
    end
    if repr == "Escape" then
        context:clear()
        return 1
    end
    if repr == "space" then
        if context:has_menu() then
            context:confirm_current_selection()
        end
        return 1
    end
    return 2
end

local function translator(input, seg, env)
    local results = decode(input)
    for i = 1, #results do
        local item = results[i]
        local cand = Candidate("sentence", seg.start, seg._end, item.text, "")
        cand.preedit = item.segmented
        yield(cand)
    end
end

local M = {}
M.decode = decode
M.decode_full = decode_full
M.reset_decode_cache = reset_decode_cache
M.results_equal = results_equal
M.processor = processor
M.translator = translator
return M
