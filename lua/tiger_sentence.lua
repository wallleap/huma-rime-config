-- TigerClaw-style sentence lattice for Rime, with optional Lua KN scoring.
local lexicon = require("tiger_sentence_lexicon")
local kn_reader = require("tiger_sentence_kn")
local ranks = require("tiger_sentence_ranks")
local supplement = require("tiger_sentence_supplement")

local beam_width = 200
local candidate_limit = 20
local max_raw_length = 128
local rank_penalty = 0.03
local emitted_character_reward = 2.0
local isolation_threshold = 3000
local isolation_lambda = 2.0
local BOS = kn_reader.BOS
local EOS = kn_reader.EOS
local kn_model = false
local kn_load_error = nil
local supplement_matcher = supplement.load_default()
local max_code_len = 1
for i = 1, #lexicon.lengths do
    if lexicon.lengths[i] > max_code_len then
        max_code_len = lexicon.lengths[i]
    end
end
local proper_code_prefixes = {}
for code, _ in pairs(lexicon.codes) do
    for length = 1, #code - 1 do
        proper_code_prefixes[code:sub(1, length)] = true
    end
end

local logp_cache_limit = 32768
local logp_cache = {}
local logp_cache_keys = {}
local logp_cache_next = 1
local observed_cache_limit = 32768
local observed_cache = {}
local observed_cache_keys = {}
local observed_cache_next = 1
local aggregate_during_expansion_threshold = 128
local decode_cache = {
    raw = nil,
    states = nil,
    result = nil,
    includes_early_commit = false
}
local state_separator = "\31"

-- Only committed-prefix state must be visible to both the processor and
-- translator. Keep per-key confidence state on the processor environment so
-- it does not emit a Rime property update (and a redundant UI refresh) for
-- every physical key. The old properties are read once for live migration.
local state_keys = {
    committed_text = "tiger_sentence_committed_text",
    committed_raw = "tiger_sentence_committed_raw",
    confidence = "tiger_sentence_confidence",
    -- Read and clear the old split properties once during migration.
    proposal = "tiger_sentence_proposal",
    stable = "tiger_sentence_stable",
    evidence_raw = "tiger_sentence_evidence_raw"
}

local function transient_state(context, env)
    if not env then
        return { proposal = "", stable = 0, evidence_raw = "", history = {}, suspended = false }
    end
    if not env._tiger_sentence_transient then
        local confidence = context:get_property(state_keys.confidence) or ""
        local proposal, stable, evidence_raw = confidence:match(
            "^(.-)" .. state_separator .. "(%d+)" .. state_separator .. "(.*)$")
        if proposal == nil then
            proposal = context:get_property(state_keys.proposal) or ""
            stable = context:get_property(state_keys.stable) or "0"
            evidence_raw = context:get_property(state_keys.evidence_raw) or ""
        end
        env._tiger_sentence_transient = {
            proposal = proposal,
            stable = tonumber(stable) or 0,
            evidence_raw = evidence_raw,
            history = {},
            suspended = false
        }
    end
    return env._tiger_sentence_transient
end

local function sentence_state(context, env)
    local transient = transient_state(context, env)
    return {
        committed_text = context:get_property(state_keys.committed_text) or "",
        committed_raw = context:get_property(state_keys.committed_raw) or "",
        proposal = transient.proposal,
        stable = transient.stable,
        evidence_raw = transient.evidence_raw,
        history = transient.history or {},
        suspended = transient.suspended or false
    }
end

local function set_property_if_changed(context, key, value)
    value = value or ""
    if (context:get_property(key) or "") ~= value then
        context:set_property(key, value)
    end
end

local function save_transient_state(context, state, env)
    if env then
        env._tiger_sentence_transient = {
            proposal = state.proposal or "",
            stable = state.stable or 0,
            evidence_raw = state.evidence_raw or "",
            history = state.history or {},
            suspended = state.suspended or false
        }
    end
    if env and not env._tiger_sentence_legacy_cleared then
        set_property_if_changed(context, state_keys.confidence, "")
        set_property_if_changed(context, state_keys.proposal, "")
        set_property_if_changed(context, state_keys.stable, "")
        set_property_if_changed(context, state_keys.evidence_raw, "")
        env._tiger_sentence_legacy_cleared = true
    end
end

local function save_sentence_state(context, state, env)
    set_property_if_changed(context, state_keys.committed_text, state.committed_text)
    set_property_if_changed(context, state_keys.committed_raw, state.committed_raw)
    save_transient_state(context, state, env)
end

local function reset_sentence_state(context, env)
    save_sentence_state(context, {
        committed_text = "",
        committed_raw = "",
        proposal = "",
        stable = 0,
        evidence_raw = "",
        history = {},
        suspended = false
    }, env)
end

local function ensure_kn()
    if kn_model ~= false then
        return kn_model
    end
    kn_model, kn_load_error = kn_reader.try_load()
    kn_model = kn_model or nil
    return kn_model
end

local function model_status()
    local model = ensure_kn()
    if model then
        return {
            loaded = true,
            path = model.path,
            format = model.format,
            bytes = model.bytes,
            error = nil
        }
    end
    return {
        loaded = false,
        path = nil,
        format = nil,
        bytes = 0,
        error = kn_load_error
    }
end

local function logp(prev2, prev1, target)
    local key = prev2 .. "\0" .. prev1 .. "\0" .. target
    local cached = logp_cache[key]
    if cached ~= nil then
        return cached
    end
    local model = ensure_kn()
    local value = 0
    if model then
        value = model.logp(prev2, prev1, target)
    end
    local old_key = logp_cache_keys[logp_cache_next]
    if old_key then
        logp_cache[old_key] = nil
    end
    logp_cache[key] = value
    logp_cache_keys[logp_cache_next] = key
    logp_cache_next = logp_cache_next % logp_cache_limit + 1
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
    local index = 1
    while index <= #text do
        local first = text:byte(index)
        local length = first < 0x80 and 1 or first < 0xE0 and 2 or first < 0xF0 and 3 or 4
        chars[#chars + 1] = text:sub(index, index + length - 1)
        index = index + length
    end
    return chars
end

local function candidate_chars(candidate)
    if not candidate._chars then
        candidate._chars = utf_chars(candidate.t)
    end
    return candidate._chars
end

local function eligible_candidates(candidates, selected_rank, allow_all_ranks)
    if selected_rank == 0 and allow_all_ranks then
        return candidates
    end
    local rank = selected_rank > 0 and selected_rank or 1
    local cache_key = "_rank_" .. tostring(rank)
    local cached = candidates[cache_key]
    if cached then
        return cached
    end
    local selected = {}
    for index = 1, #candidates do
        if candidates[index].r == rank then
            selected[#selected + 1] = candidates[index]
        end
    end
    candidates[cache_key] = selected
    return selected
end

local function has_observed_bigram(previous, target)
    local key = previous .. "\0" .. target
    local cached = observed_cache[key]
    if cached ~= nil then
        return cached
    end
    local model = ensure_kn()
    local value = model and model.has_observed_bigram and
        model.has_observed_bigram(previous, target) or false
    local old_key = observed_cache_keys[observed_cache_next]
    if old_key then
        observed_cache[old_key] = nil
    end
    observed_cache[key] = value
    observed_cache_keys[observed_cache_next] = key
    observed_cache_next = observed_cache_next % observed_cache_limit + 1
    return value
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
            local left_hit = index > 1 and has_observed_bigram(chars[index - 1], chars[index])
            local right_hit = index < #chars and has_observed_bigram(chars[index], chars[index + 1])
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

local function state_better(left, right)
    local left_rank = left.max_rank or 1
    local right_rank = right.max_rank or 1
    if left_rank ~= right_rank then
        return left_rank < right_rank
    end
    if left.score == right.score then
        return left.text < right.text
    end
    return left.score > right.score
end

local function duplicate_better(item, previous)
    local item_rank = item.max_rank or 1
    local previous_rank = previous.max_rank or 1
    return item_rank < previous_rank or
        (item_rank == previous_rank and item.score > previous.score)
end

local function logsumexp(left, right)
    local maximum = math.max(left, right)
    return maximum + math.log(math.exp(left - maximum) + math.exp(right - maximum))
end

local function new_bucket()
    return {}
end

local function add_aggregated(bucket, item)
    local best = bucket._best
    local mass = bucket._mass
    local previous = best[item.text]
    local item_mass = item.mass_score or item.score
    if not previous then
        best[item.text] = item
        mass[item.text] = item_mass
        bucket._order[#bucket._order + 1] = item.text
    else
        mass[item.text] = logsumexp(mass[item.text], item_mass)
        if duplicate_better(item, previous) then
            best[item.text] = item
        end
    end
    best[item.text].mass_score = mass[item.text]
end

local function ensure_aggregated(bucket)
    if bucket._best then
        return
    end
    local best = {}
    local mass = {}
    local order = {}
    for i = 1, #bucket do
        local item = bucket[i]
        local previous = best[item.text]
        local item_mass = item.mass_score or item.score
        if mass[item.text] == nil then
            mass[item.text] = item_mass
        else
            mass[item.text] = logsumexp(mass[item.text], item_mass)
        end
        if not previous then
            order[#order + 1] = item.text
            best[item.text] = item
        elseif duplicate_better(item, previous) then
            best[item.text] = item
        end
    end
    for i = #bucket, 1, -1 do
        bucket[i] = nil
    end
    for i = 1, #order do
        best[order[i]].mass_score = mass[order[i]]
    end
    bucket._best = best
    bucket._mass = mass
    bucket._order = order
end

local function add_state(bucket, item)
    if bucket._best then
        add_aggregated(bucket, item)
        return
    end
    bucket[#bucket + 1] = item
    if #bucket >= aggregate_during_expansion_threshold then
        ensure_aggregated(bucket)
    end
end

local function sift_worst_up(heap, index)
    while index > 1 do
        local parent = math.floor(index / 2)
        if not state_better(heap[parent], heap[index]) then
            return
        end
        heap[parent], heap[index] = heap[index], heap[parent]
        index = parent
    end
end

local function sift_worst_down(heap, index)
    while true do
        local left = index * 2
        if left > #heap then
            return
        end
        local right = left + 1
        local worse = left
        if right <= #heap and state_better(heap[left], heap[right]) then
            worse = right
        end
        if not state_better(heap[index], heap[worse]) then
            return
        end
        heap[index], heap[worse] = heap[worse], heap[index]
        index = worse
    end
end

local function select_exact_top(values, limit)
    local heap = {}
    for i = 1, #values do
        local item = values[i]
        if #heap < limit then
            heap[#heap + 1] = item
            sift_worst_up(heap, #heap)
        elseif state_better(item, heap[1]) then
            heap[1] = item
            sift_worst_down(heap, 1)
        end
    end
    table.sort(heap, state_better)
    return heap
end

local function dedup_limit(bucket, limit)
    if not bucket then
        return new_bucket()
    end
    ensure_aggregated(bucket)
    local result = {}
    for i = 1, #bucket._order do
        local selected = bucket._best[bucket._order[i]]
        if selected then
            result[#result + 1] = selected
        end
    end
    local truncated_now = #result > limit
    local truncated = (bucket._truncated or false) or truncated_now
    if truncated_now then
        result = select_exact_top(result, limit)
    else
        table.sort(result, state_better)
    end
    local limited = new_bucket()
    for i = 1, #result do
        limited[i] = result[i]
    end
    limited._truncated = truncated
    return limited
end

local function new_states(length)
    local states = {}
    for index = 0, length do
        states[index] = new_bucket()
    end
    add_state(states[0], {
        score = 0,
        mass_score = 0,
        text = "",
        segmented = "",
        prev2 = BOS,
        prev1 = BOS,
        max_rank = 1,
        supplement_state = 1,
        supplement_score = 0.0,
        previous = nil,
        text_length = 0,
        raw_length = 0
    })
    return states
end

local function expand_range(raw, states, from_pos, length, minimum_consumed_end)
    minimum_consumed_end = minimum_consumed_end or -1
    local allow_all_ranks = length <= 4
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
                        if consumed_end > minimum_consumed_end and
                            not (length > 1 and consumed_end - position < 2) then
                            local selected_candidates = eligible_candidates(
                                candidates, selected_rank, allow_all_ranks)
                            for c = 1, #current do
                                local item = current[c]
                                for k = 1, #selected_candidates do
                                    local candidate = selected_candidates[k]
                                    local score = item.score
                                    local prev2, prev1 = item.prev2, item.prev1
                                    local supplement_state = item.supplement_state or 1
                                    local supplement_added = 0.0
                                    local chars = candidate_chars(candidate)
                                    for ci = 1, #chars do
                                        score = score + logp(prev2, prev1, chars[ci])
                                        score = score + emitted_character_reward
                                        local supplement_reward
                                        supplement_state, supplement_reward = supplement.advance(
                                            supplement_matcher, supplement_state, chars[ci])
                                        score = score + supplement_reward
                                        supplement_added = supplement_added + supplement_reward
                                        prev2 = prev1
                                        prev1 = chars[ci]
                                    end
                                    if selected_rank == 0 then
                                        score = score - rank_penalty * math.log(1.0 + candidate.r - 1)
                                    end
                                    local piece = raw:sub(position + 1, consumed_end)
                                    local segmented = item.segmented
                                    if segmented == "" then
                                        segmented = piece
                                    else
                                        segmented = segmented .. " " .. piece
                                    end
                                    local text = item.text .. candidate.t
                                    add_state(states[consumed_end], {
                                        score = score,
                                        mass_score = (item.mass_score or item.score) +
                                            score - item.score - supplement_added,
                                        text = text,
                                        segmented = segmented,
                                        prev2 = prev2,
                                        prev1 = prev1,
                                        max_rank = math.max(item.max_rank or 1, candidate.r),
                                        supplement_state = supplement_state,
                                        supplement_score = (item.supplement_score or 0.0) +
                                            supplement_added,
                                        previous = item,
                                        text_length = #text,
                                        raw_length = consumed_end
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function add_early_commit_states(values, mass_by_text, best_by_text)
    for i = 1, #values do
        local item = values[i]
        if item.text and item.text ~= "" then
            local ending_adjustment = logp(item.prev2, item.prev1, EOS) -
                isolation_penalty(item.text)
            local confidence_score = (item.mass_score or item.score) + ending_adjustment
            local previous_mass = mass_by_text[item.text]
            if previous_mass == nil then
                mass_by_text[item.text] = confidence_score
            else
                mass_by_text[item.text] = logsumexp(previous_mass, confidence_score)
            end
            local previous = best_by_text[item.text]
            if not previous or confidence_score > previous.confidence_score then
                best_by_text[item.text] = {
                    score = item.score + ending_adjustment,
                    confidence_score = confidence_score,
                    text = item.text,
                    segmented = item.segmented,
                    prev2 = item.prev2,
                    prev1 = item.prev1,
                    max_rank = math.max(1, item.max_rank or 1),
                    supplement_score = item.supplement_score or 0.0,
                    path = item
                }
            end
        end
    end
end

local function incomplete_code_tail(tail)
    if tail == "" or not tail:match("^[A-Za-z]+$") or
        not proper_code_prefixes[tail] then
        return false
    end
    return #tail < 2 or lexicon.codes[tail] == nil
end

local function build_early_commit_candidates(raw, states, completed)
    local mass_by_text = {}
    local best_by_text = {}
    local truncated = completed._truncated or false
    local uses_incomplete_tail = false
    add_early_commit_states(completed, mass_by_text, best_by_text)

    local maximum_tail_length = math.min(max_code_len - 1, #raw - 1)
    for tail_length = 1, maximum_tail_length do
        local consumed_length = #raw - tail_length
        local tail = raw:sub(consumed_length + 1)
        if incomplete_code_tail(tail) and states[consumed_length] then
            local partial = dedup_limit(states[consumed_length], beam_width)
            states[consumed_length] = partial
            if #partial > 0 then
                uses_incomplete_tail = true
                truncated = truncated or (partial._truncated or false)
                add_early_commit_states(partial, mass_by_text, best_by_text)
            end
        end
    end

    if not uses_incomplete_tail then
        return {}, false, false, false
    end

    local candidates = {}
    for text, candidate in pairs(best_by_text) do
        candidate.confidence_score = mass_by_text[text]
        candidates[#candidates + 1] = candidate
    end
    table.sort(candidates, function(left, right)
        if left.confidence_score == right.confidence_score then
            return left.text < right.text
        end
        return left.confidence_score > right.confidence_score
    end)
    return candidates, truncated, true
end

local function emit(raw, states, length, include_early_commit)
    local completed = dedup_limit(states[length], beam_width)
    local result = {}
    for i = 1, #completed do
        local item = completed[i]
        result[i] = {
            score = item.score + logp(item.prev2, item.prev1, EOS) - isolation_penalty(item.text),
            confidence_score = (item.mass_score or item.score) +
                logp(item.prev2, item.prev1, EOS) - isolation_penalty(item.text),
            text = item.text,
            segmented = item.segmented,
            prev2 = item.prev2,
            prev1 = item.prev1,
            max_rank = math.max(1, item.max_rank or 1),
            supplement_score = item.supplement_score or 0.0,
            path = item
        }
    end
    table.sort(result, function(left, right)
        if left.max_rank ~= right.max_rank then
            return left.max_rank < right.max_rank
        end
        if left.score == right.score then
            return left.text < right.text
        end
        return left.score > right.score
    end)
    result.confidence_truncated = completed._truncated or false
    result.early_commit_candidates = {}
    result.early_commit_confidence_truncated = false
    result.early_commit_uses_incomplete_tail = false
    result.early_commit_prefers_incomplete_tail = false
    if include_early_commit then
        local early, early_truncated, uses_incomplete =
            build_early_commit_candidates(raw, states, completed)
        result.early_commit_candidates = early
        result.early_commit_confidence_truncated = early_truncated
        result.early_commit_uses_incomplete_tail = uses_incomplete
        if uses_incomplete and #early > 0 then
            if #result == 0 then
                result.early_commit_prefers_incomplete_tail = true
            else
                local full_top = result[1]
                for i = 2, #result do
                    if (result[i].confidence_score or result[i].score) >
                        (full_top.confidence_score or full_top.score) then
                        full_top = result[i]
                    end
                end
                result.early_commit_prefers_incomplete_tail = early[1].text ~= full_top.text
            end
        end
    end
    return result
end

local function results_equal(left, right)
    if #left ~= #right then
        return false
    end
    if (left.confidence_truncated or false) ~= (right.confidence_truncated or false) then
        return false
    end
    if (left.early_commit_confidence_truncated or false) ~=
        (right.early_commit_confidence_truncated or false) or
        (left.early_commit_uses_incomplete_tail or false) ~=
        (right.early_commit_uses_incomplete_tail or false) or
        (left.early_commit_prefers_incomplete_tail or false) ~=
        (right.early_commit_prefers_incomplete_tail or false) then
        return false
    end
    for i = 1, #left do
        if left[i].text ~= right[i].text
            or left[i].segmented ~= right[i].segmented
            or left[i].score ~= right[i].score
            or (left[i].confidence_score or left[i].score) ~=
                (right[i].confidence_score or right[i].score)
            or (left[i].supplement_score or 0.0) ~=
                (right[i].supplement_score or 0.0)
            or (left[i].max_rank or 1) ~= (right[i].max_rank or 1) then
            return false
        end
    end
    local left_early = left.early_commit_candidates or {}
    local right_early = right.early_commit_candidates or {}
    if #left_early ~= #right_early then return false end
    for i = 1, #left_early do
        if left_early[i].text ~= right_early[i].text or
            left_early[i].segmented ~= right_early[i].segmented or
            left_early[i].score ~= right_early[i].score or
            left_early[i].confidence_score ~= right_early[i].confidence_score or
            (left_early[i].supplement_score or 0.0) ~=
                (right_early[i].supplement_score or 0.0) or
            (left_early[i].max_rank or 1) ~= (right_early[i].max_rank or 1) then
            return false
        end
    end
    return true
end

local function decode_full(raw_code, include_early_commit)
    local raw = normalize(raw_code)
    if raw == "" or not has_letter(raw) then
        return {}
    end
    local length = #raw
    local states = new_states(length)
    expand_range(raw, states, 0, length)
    return emit(raw, states, length, include_early_commit or false)
end

local function decode(raw_code, include_early_commit)
    local raw = normalize(raw_code)
    if raw == "" or not has_letter(raw) then
        decode_cache.raw = raw
        decode_cache.states = nil
        decode_cache.result = {}
        decode_cache.includes_early_commit = include_early_commit or false
        return decode_cache.result
    end
    if decode_cache.raw == raw and decode_cache.result and
        (not include_early_commit or decode_cache.includes_early_commit) then
        return decode_cache.result
    end

    local length = #raw
    local states = nil
    local old_raw = decode_cache.raw
    local old_states = decode_cache.states
    if old_states and type(old_raw) == "string" and old_raw ~= "" then
        local old_n = #old_raw
        -- A one-key segment is legal only when the whole input is one key.
        -- Crossing that boundary, or the four-key all-rank boundary, changes
        -- which edges exist in the reused prefix.
        if old_n == 1 or length == 1 or (old_n <= 4) ~= (length <= 4) then
            states = nil
        elseif length > old_n and raw:sub(1, old_n) == old_raw then
            local max_consume = max_code_len + trailing_selector_span(raw)
            local from_pos = math.max(0, old_n + 1 - max_consume)
            states = old_states
            for index = old_n + 1, length do
                states[index] = new_bucket()
            end
            expand_range(raw, states, from_pos, length, old_n)
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

    local result = emit(raw, states, length, include_early_commit or false)
    decode_cache.raw = raw
    decode_cache.states = states
    decode_cache.result = result
    decode_cache.includes_early_commit = include_early_commit or false
    return result
end

local function trim_segmented_after_raw_prefix(segmented, raw_prefix_length)
    if not segmented or segmented == "" or raw_prefix_length <= 0 then
        return segmented or ""
    end
    local raw_count = 0
    local index = 1
    while index <= #segmented and raw_count < raw_prefix_length do
        if segmented:sub(index, index) ~= " " then
            raw_count = raw_count + 1
        end
        index = index + 1
    end
    while index <= #segmented and segmented:sub(index, index) == " " do
        index = index + 1
    end
    return index <= #segmented and segmented:sub(index) or ""
end

local function find_raw_length_for_text(text, candidates)
    local text_length = #text
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.text:sub(1, text_length) == text then
            local state = candidate.path
            while state do
                if state.text_length == text_length then
                    return state.raw_length
                end
                state = state.previous
            end
        end
    end
    return 0
end

local function raw_lengths_for_proposal(proposal, candidates)
    local lengths = {}
    local prefix_by_length = {}
    local prefix = ""
    local chars = utf_chars(proposal)
    for i = 1, #chars do
        prefix = prefix .. chars[i]
        prefix_by_length[#prefix] = prefix
    end
    local found = 0
    for i = 1, #candidates do
        local candidate = candidates[i]
        local state = candidate.path
        while state do
            local wanted = prefix_by_length[state.text_length]
            if wanted and lengths[wanted] == nil and
                candidate.text:sub(1, state.text_length) == wanted then
                lengths[wanted] = state.raw_length
                found = found + 1
            end
            state = state.previous
        end
        if found == #chars then break end
    end
    return lengths
end

local function common_history_prefix(history)
    if #history == 0 then return "" end
    local common = utf_chars(history[1].proposal or "")
    for index = 2, #history do
        local chars = utf_chars(history[index].proposal or "")
        local count = math.min(#common, #chars)
        local matched = 0
        while matched < count and common[matched + 1] == chars[matched + 1] do
            matched = matched + 1
        end
        while #common > matched do common[#common] = nil end
        if #common == 0 then return "" end
    end
    return table.concat(common)
end

local function stable_history_raw_length(history, text)
    if text == "" or #history < 3 then return 0 end
    local stable = 0
    for i = 1, #history do
        local raw_length = (history[i].raw_lengths or {})[text] or 0
        if raw_length <= 0 then return 0 end
        if stable == 0 then
            stable = raw_length
        elseif stable ~= raw_length then
            return 0
        end
    end
    return stable
end

local function confidence_proposal(candidates, threshold)
    if #candidates == 0 then
        return ""
    end
    local max_score = candidates[1].confidence_score or candidates[1].score
    for i = 2, #candidates do
        local score = candidates[i].confidence_score or candidates[i].score
        if score > max_score then max_score = score end
    end
    local total = 0
    for i = 1, #candidates do
        total = total + math.exp((candidates[i].confidence_score or candidates[i].score) - max_score)
    end

    local prefix_mass = {}
    local prefix_length = {}
    local prefix_order = {}
    for i = 1, #candidates do
        local weight = math.exp((candidates[i].confidence_score or candidates[i].score) - max_score)
        local chars = utf_chars(candidates[i].text)
        local prefix = ""
        for length = 1, #chars - 1 do
            prefix = prefix .. chars[length]
            if prefix_mass[prefix] == nil then
                prefix_mass[prefix] = 0
                prefix_length[prefix] = length
                prefix_order[#prefix_order + 1] = prefix
            end
            prefix_mass[prefix] = prefix_mass[prefix] + weight
        end
    end

    local proposal = ""
    local proposal_length = 0
    for index = 1, #prefix_order do
        local prefix = prefix_order[index]
        local length = prefix_length[prefix]
        if prefix_mass[prefix] / total >= threshold and length > proposal_length then
            proposal = prefix
            proposal_length = length
        end
    end
    return proposal
end

local function try_early_commit(env)
    local context = env.engine.context
    local state = sentence_state(context, env)
    local live_raw = context.input or ""

    if not context:get_option("tiger_sentence_early_commit") then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end

    if state.suspended then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end

    -- The first four raw encoding keys are never counted as stable evidence.
    if #live_raw + #state.committed_raw <= 4 then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end

    local full_raw = state.committed_raw .. live_raw
    local decoded = decode(full_raw, true)
    local confidence_source = decoded
    local confidence_truncated = decoded.confidence_truncated
    if decoded.early_commit_uses_incomplete_tail then
        confidence_source = decoded.early_commit_candidates or {}
        confidence_truncated = decoded.early_commit_confidence_truncated or false
    end
    if confidence_truncated then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end
    local candidates = {}
    for i = 1, #confidence_source do
        local candidate = confidence_source[i]
        if state.committed_text == "" or
            candidate.text:sub(1, #state.committed_text) == state.committed_text then
            candidates[#candidates + 1] = candidate
        end
    end
    if #candidates == 0 then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end

    local proposal = confidence_proposal(candidates, 0.995)
    local visible_top = nil
    for i = 1, #decoded do
        if state.committed_text == "" or
            decoded[i].text:sub(1, #state.committed_text) == state.committed_text then
            visible_top = decoded[i]
            break
        end
    end
    if visible_top and (visible_top.supplement_score or 0.0) > 0.0 then
        local supplement_top = visible_top.text
        while #proposal > #state.committed_text and
            supplement_top:sub(1, #proposal) ~= proposal do
            local chars = utf_chars(proposal)
            chars[#chars] = nil
            proposal = table.concat(chars)
        end
    end
    if proposal == "" or #proposal <= #state.committed_text then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return
    end

    local history = state.history or {}
    local previous_raw = #history > 0 and history[#history].raw or ""
    local extends_evidence = previous_raw ~= "" and
        #full_raw == #previous_raw + 1 and
        full_raw:sub(1, #previous_raw) == previous_raw
    if not extends_evidence then
        history = {}
    end
    history[#history + 1] = {
        proposal = proposal,
        raw = full_raw,
        raw_lengths = raw_lengths_for_proposal(proposal, candidates)
    }
    while #history > 3 do table.remove(history, 1) end
    state.history = history
    state.proposal = proposal
    state.stable = #history
    state.evidence_raw = full_raw
    save_transient_state(context, state, env)
    if #history < 3 then return end

    local stable_proposal = common_history_prefix(history)
    local consumed = stable_history_raw_length(history, stable_proposal)
    while #stable_proposal > #state.committed_text and consumed == 0 do
        local chars = utf_chars(stable_proposal)
        chars[#chars] = nil
        stable_proposal = table.concat(chars)
        consumed = stable_history_raw_length(history, stable_proposal)
    end
    if consumed <= #state.committed_raw or consumed > #full_raw then return end
    local commit = stable_proposal:sub(#state.committed_text + 1)
    if #utf_chars(commit) < 1 or #live_raw < 3 then return end
    state.committed_text = stable_proposal
    state.committed_raw = full_raw:sub(1, consumed)
    state.proposal = stable_proposal
    state.stable = 0
    state.evidence_raw = ""
    state.history = {}
    env.engine:commit_text(commit)
    context:clear()
    save_sentence_state(context, state, env)
    local remaining = full_raw:sub(consumed + 1)
    if remaining ~= "" then context:push_input(remaining) end
end

local function reset_decode_cache()
    decode_cache.raw = nil
    decode_cache.states = nil
    decode_cache.result = nil
    decode_cache.includes_early_commit = false
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
    local state = sentence_state(context, env)
    local repr = key_event:repr()
    local ch = is_plain_char_key(key_event, repr)
    if ch then
        if not context:is_composing() and
            (state.committed_raw ~= "" or state.proposal ~= "" or
             state.evidence_raw ~= "" or state.suspended) then
            reset_sentence_state(context, env)
            state = sentence_state(context, env)
        end
        if #(context.input or "") >= max_raw_length then
            return 1
        end
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
        try_early_commit(env)
        return 1
    end
    if not context:is_composing() then
        return 2
    end
    if repr == "Return" or repr == "KP_Enter" then
        env.engine:commit_text(context.input)
        context:clear()
        reset_sentence_state(context, env)
        return 1
    end
    if repr == "Escape" then
        context:clear()
        reset_sentence_state(context, env)
        return 1
    end
    if repr == "BackSpace" or repr == "Delete" then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        save_transient_state(context, state, env)
        return 2
    end
    if repr == "Up" or repr == "Down" or repr == "Page_Up" or repr == "Page_Down" or
        repr == "Tab" or repr == "ISO_Left_Tab" then
        state.proposal = ""
        state.stable = 0
        state.evidence_raw = ""
        state.history = {}
        state.suspended = true
        save_transient_state(context, state, env)
        return 2
    end
    if repr == "space" then
        if context:has_menu() then
            context:confirm_current_selection()
        end
        reset_sentence_state(context, env)
        return 1
    end
    return 2
end

local function translator(input, seg, env)
    local context = env.engine.context
    local committed_text = context:get_property(state_keys.committed_text) or ""
    local committed_raw = context:get_property(state_keys.committed_raw) or ""
    local raw = committed_raw .. input
    local results = decode(raw)
    local yielded = 0
    for i = 1, #results do
        local item = results[i]
        if committed_text == "" or item.text:sub(1, #committed_text) == committed_text then
            local text = committed_text == "" and item.text or item.text:sub(#committed_text + 1)
            local preedit = committed_raw == "" and item.segmented or
                trim_segmented_after_raw_prefix(item.segmented, #committed_raw)
            if text ~= "" then
                local cand = Candidate("sentence", seg.start, seg._end, text, "")
                cand.preedit = preedit
                yield(cand)
                yielded = yielded + 1
                if yielded >= candidate_limit then return end
            end
        end
    end
end

local M = {}
M.decode = decode
M.decode_full = decode_full
M.reset_decode_cache = reset_decode_cache
M.results_equal = results_equal
M.model_status = model_status
M.supplement_status = function()
    return {
        path = supplement_matcher.path,
        count = supplement_matcher.count or 0,
        error = supplement_matcher.error
    }
end
M.find_raw_length_for_text = find_raw_length_for_text
M.confidence_proposal = confidence_proposal
M.processor = processor
M.translator = translator
return M
