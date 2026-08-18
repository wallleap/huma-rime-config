-- Pure Lua Kneser-Ney V2 reader (TCSKNM01). First version: load whole file.
local BOS = "\2"
local EOS = "\3"
local SHIFT = 2097152
local MASK = 2097151

local M = {
    BOS = BOS,
    EOS = EOS
}

local function file_exists(path)
    local file = io.open(path, "rb")
    if not file then
        return false
    end
    file:close()
    return true
end

function M.candidate_paths()
    local paths = {}
    if rime_api then
        local user_dir = rime_api.get_user_data_dir and rime_api.get_user_data_dir()
        local shared_dir = rime_api.get_shared_data_dir and rime_api.get_shared_data_dir()
        if user_dir and user_dir ~= "" then
            paths[#paths + 1] = user_dir .. "/models/sentence-ngram-v2.bin"
            paths[#paths + 1] = user_dir .. "/sentence-ngram-v2.bin"
        end
        if shared_dir and shared_dir ~= "" then
            paths[#paths + 1] = shared_dir .. "/models/sentence-ngram-v2.bin"
        end
    end
    paths[#paths + 1] = "C:/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-v2.bin"
    paths[#paths + 1] = "/mnt/c/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-v2.bin"
    return paths
end

function M.load(path)
    local file = assert(io.open(path, "rb"), "cannot open n-gram: " .. path)
    local data = file:read("*a")
    file:close()
    assert(data and #data > 32, "empty n-gram: " .. path)
    assert(data:sub(1, 8) == "TCSKNM01", "not a TCSKNM01 model: " .. path)

    local function i32(off)
        return (string.unpack("<i4", data, off + 1))
    end
    local function u64(off)
        return (string.unpack("<I8", data, off + 1))
    end
    local function f32(off)
        return (string.unpack("<f", data, off + 1))
    end

    assert(i32(8) == 1, "unsupported n-gram version")
    local uni_count = i32(12)
    local pos = 16
    local uni_off = pos
    pos = pos + uni_count * 8
    local bi_count = u64(pos)
    pos = pos + 8
    local bi_off = pos
    pos = pos + bi_count * 12
    local bi_ctx_count = i32(pos)
    pos = pos + 4
    local bi_ctx_off = pos
    pos = pos + bi_ctx_count * 8
    local tri_count = u64(pos)
    pos = pos + 8
    local tri_off = pos
    pos = pos + tri_count * 12
    local tri_ctx_count = u64(pos)
    pos = pos + 8
    local tri_ctx_off = pos
    local unknown = f32(uni_off + 4)

    local function lookup_i32(offset, count, key, fallback)
        local low, high = 0, count
        while low < high do
            local middle = low + ((high - low) // 2)
            local value = i32(offset + middle * 8)
            if value < key then
                low = middle + 1
            else
                high = middle
            end
        end
        if low >= count then
            return fallback
        end
        local at = offset + low * 8
        if i32(at) == key then
            return f32(at + 4)
        end
        return fallback
    end

    local function lookup_u64(offset, count, key, fallback)
        local low, high = 0, count
        while low < high do
            local middle = low + ((high - low) // 2)
            local value = u64(offset + middle * 12)
            if value < key then
                low = middle + 1
            else
                high = middle
            end
        end
        if low >= count then
            return fallback
        end
        local at = offset + low * 12
        if u64(at) == key then
            return f32(at + 8)
        end
        return fallback
    end

    local function scalar(token)
        if not token or token == "" then
            return 0
        end
        if token == BOS or token == EOS then
            return string.byte(token)
        end
        return utf8.codepoint(token)
    end

    local function pack2(first, second)
        return first * SHIFT + (second & MASK)
    end
    local function pack3(first, second, third)
        return pack2(first, second) * SHIFT + (third & MASK)
    end

    local function logp(prev2, prev1, target)
        local first = scalar(prev2)
        local second = scalar(prev1)
        local third = scalar(target)
        local unigram = lookup_i32(uni_off, uni_count, third, unknown)
        local bigram = lookup_u64(bi_off, bi_count, pack2(second, third), 0.0)
        local bigram_lambda = lookup_i32(bi_ctx_off, bi_ctx_count, second, 1.0)
        bigram = bigram + bigram_lambda * unigram
        local trigram = lookup_u64(tri_off, tri_count, pack3(first, second, third), 0.0)
        local trigram_lambda = lookup_u64(tri_ctx_off, tri_ctx_count, pack2(first, second), 1.0)
        trigram = trigram + trigram_lambda * bigram
        if trigram < 1e-300 then
            trigram = 1e-300
        end
        return math.log(trigram)
    end

    local function has_observed_bigram(prev, target)
        local left = scalar(prev)
        local right = scalar(target)
        local key = pack2(left, right)
        local low, high = 0, bi_count
        while low < high do
            local middle = low + ((high - low) // 2)
            local value = u64(bi_off + middle * 12)
            if value < key then
                low = middle + 1
            else
                high = middle
            end
        end
        return low < bi_count and u64(bi_off + low * 12) == key
    end

    return {
        path = path,
        bytes = #data,
        logp = logp,
        has_observed_bigram = has_observed_bigram
    }
end

function M.try_load()
    for _, path in ipairs(M.candidate_paths()) do
        if file_exists(path) then
            local ok, model = pcall(M.load, path)
            if ok then
                return model
            end
        end
    end
    return nil
end

return M
