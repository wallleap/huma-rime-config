-- Pure Lua Kneser-Ney V2 reader. TCSKNM02 uses paged I/O and a bounded cache.
local BOS = "\2"
local EOS = "\3"
local SHIFT = 2097152
local MOBILE_HEADER_SIZE = 104
local MOBILE_CACHE_BYTES = 8 * 1024 * 1024
local CONTEXT_CACHE_ENTRIES = 16384

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
    local mobile_paths = {}
    local legacy_paths = {}
    if rime_api then
        local user_dir = rime_api.get_user_data_dir and rime_api.get_user_data_dir()
        local shared_dir = rime_api.get_shared_data_dir and rime_api.get_shared_data_dir()
        if user_dir and user_dir ~= "" then
            mobile_paths[#mobile_paths + 1] = user_dir .. "/models/sentence-ngram-mobile.bin"
            mobile_paths[#mobile_paths + 1] = user_dir .. "/sentence-ngram-mobile.bin"
            legacy_paths[#legacy_paths + 1] = user_dir .. "/models/sentence-ngram-v2.bin"
            legacy_paths[#legacy_paths + 1] = user_dir .. "/sentence-ngram-v2.bin"
        end
        if shared_dir and shared_dir ~= "" then
            mobile_paths[#mobile_paths + 1] = shared_dir .. "/models/sentence-ngram-mobile.bin"
            legacy_paths[#legacy_paths + 1] = shared_dir .. "/models/sentence-ngram-v2.bin"
        end
    end
    mobile_paths[#mobile_paths + 1] = "C:/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-mobile.bin"
    mobile_paths[#mobile_paths + 1] = "/mnt/c/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-mobile.bin"
    legacy_paths[#legacy_paths + 1] = "C:/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-v2.bin"
    legacy_paths[#legacy_paths + 1] = "/mnt/c/Archive/tigerclaw_sentence_ml/runtime/sentence-ngram-v2.bin"
    for _, path in ipairs(legacy_paths) do
        mobile_paths[#mobile_paths + 1] = path
    end
    return mobile_paths
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
    -- Avoid parser-level bitwise syntax; model scoring still requires the
    -- string.unpack and utf8 APIs supplied by Lua 5.3+ Rime builds.
    return first * SHIFT + (second % SHIFT)
end

local function load_legacy(path)
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
        local middle = low + math.floor((high - low) / 2)
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
        local middle = low + math.floor((high - low) / 2)
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

    local function pack3(first, second, third)
        return pack2(first, second) * SHIFT + (third % SHIFT)
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
        local middle = low + math.floor((high - low) / 2)
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
        format = "TCSKNM01",
        logp = logp,
        has_observed_bigram = has_observed_bigram
    }
end

local function load_mobile(path)
    local file = assert(io.open(path, "rb"), "cannot open n-gram: " .. path)
    local header = file:read(MOBILE_HEADER_SIZE)
    assert(header and #header == MOBILE_HEADER_SIZE, "truncated mobile n-gram: " .. path)
    assert(header:sub(1, 8) == "TCSKNM02", "not a TCSKNM02 model: " .. path)

    local version, header_size, file_size, index_stride, _, uni_count, _, uni_off,
        bi_ctx_count, bi_index_count, bi_blocks_off, bi_index_off, tri_ctx_count,
        tri_index_count, _, tri_blocks_off, tri_index_off =
        string.unpack("<I4I4I8I4I4I4I4I8I4I4I8I8I8I4I4I8I8", header, 9)
    assert(version == 1 and header_size == MOBILE_HEADER_SIZE, "unsupported mobile n-gram version")
    assert(index_stride >= 16 and bi_blocks_off < bi_index_off, "invalid mobile bigram layout")
    assert(bi_index_off < tri_blocks_off and tri_blocks_off < tri_index_off, "invalid mobile trigram layout")
    local actual_size = assert(file:seek("end"))
    assert(actual_size == file_size, "mobile n-gram size mismatch")

    local function read_at(offset, count)
        assert(file:seek("set", offset), "cannot seek n-gram")
        local value = file:read(count)
        assert(value and #value == count, "truncated mobile n-gram")
        return value
    end

    local unigrams = read_at(uni_off, uni_count * 8)
    local bi_index = read_at(bi_index_off, bi_index_count * 16)
    local tri_index = read_at(tri_index_off, tri_index_count * 16)
    local unknown = string.unpack("<f", unigrams, 5)

    local cache = {}
    local cache_bytes = 0
    local lru_head = nil
    local lru_tail = nil
    local context_caches = {
        b = { values = {}, keys = {}, next = 1 },
        t = { values = {}, keys = {}, next = 1 }
    }

    local function unlink(entry)
        if entry.previous then
            entry.previous.next = entry.next
        else
            lru_head = entry.next
        end
        if entry.next then
            entry.next.previous = entry.previous
        else
            lru_tail = entry.previous
        end
    end

    local function touch(entry)
        if lru_head == entry then
            return
        end
        if entry.previous or entry.next or lru_tail == entry then
            unlink(entry)
        end
        entry.previous = nil
        entry.next = lru_head
        if lru_head then
            lru_head.previous = entry
        else
            lru_tail = entry
        end
        lru_head = entry
    end

    local function index_key(data, index)
        return string.unpack("<I8", data, index * 16 + 1)
    end

    local function find_page(data, count, key)
        local low, high = 0, count
        while low < high do
        local middle = low + math.floor((high - low) / 2)
            if index_key(data, middle) <= key then
                low = middle + 1
            else
                high = middle
            end
        end
        return low - 1
    end

    local function get_page(kind, index_data, index_count, page, section_end)
        local cache_key = kind .. page
        local entry = cache[cache_key]
        if entry then
            touch(entry)
            return entry.data
        end
        local at = page * 16 + 1
        local offset = string.unpack("<I8", index_data, at + 8)
        local next_offset = section_end
        if page + 1 < index_count then
            next_offset = string.unpack("<I8", index_data, at + 24)
        end
        local data = read_at(offset, next_offset - offset)
        entry = { key = cache_key, data = data, bytes = #data }
        cache[cache_key] = entry
        cache_bytes = cache_bytes + entry.bytes
        touch(entry)
        while cache_bytes > MOBILE_CACHE_BYTES and lru_tail and lru_tail ~= entry do
            local victim = lru_tail
            unlink(victim)
            cache[victim.key] = nil
            cache_bytes = cache_bytes - victim.bytes
        end
        return data
    end

    local function lookup_unigram(key, fallback)
        local low, high = 0, uni_count
        while low < high do
            local middle = low + math.floor((high - low) / 2)
            local value = string.unpack("<i4", unigrams, middle * 8 + 1)
            if value < key then low = middle + 1 else high = middle end
        end
        if low < uni_count then
            local at = low * 8 + 1
            if string.unpack("<i4", unigrams, at) == key then
                return string.unpack("<f", unigrams, at + 4)
            end
        end
        return fallback
    end

    local function lookup_context(kind, index_data, index_count, context_count, section_end, key, target)
        local context_cache = context_caches[kind]
        local cached_context = context_cache.values[key]
        if cached_context then
            if cached_context.missing then
                return 1.0, 0.0, false
            end
            local data = get_page(
                kind, index_data, index_count, cached_context.page, section_end)
            local low, high = 0, cached_context.successor_count
            while low < high do
                local middle = low + math.floor((high - low) / 2)
                local value = string.unpack(
                    "<I4", data, cached_context.successor_position + middle * 8)
                if value < target then low = middle + 1 else high = middle end
            end
            if low < cached_context.successor_count then
                local at = cached_context.successor_position + low * 8
                if string.unpack("<I4", data, at) == target then
                    return cached_context.lambda, string.unpack("<f", data, at + 4), true
                end
            end
            return cached_context.lambda, 0.0, false
        end

        local function remember(value)
            local old_key = context_cache.keys[context_cache.next]
            if old_key ~= nil then
                context_cache.values[old_key] = nil
            end
            context_cache.values[key] = value
            context_cache.keys[context_cache.next] = key
            context_cache.next = context_cache.next % CONTEXT_CACHE_ENTRIES + 1
        end

        local page = find_page(index_data, index_count, key)
        if page < 0 then
            remember({ missing = true })
            return 1.0, 0.0, false
        end
        local data = get_page(kind, index_data, index_count, page, section_end)
        local position = 1
        local remaining = math.min(index_stride, context_count - page * index_stride)
        for _ = 1, remaining do
            local context_key, lambda, successor_count
            context_key, lambda, successor_count, position = string.unpack("<I8fI4", data, position)
            if context_key == key then
                remember({
                    page = page,
                    lambda = lambda,
                    successor_count = successor_count,
                    successor_position = position
                })
                local low, high = 0, successor_count
                while low < high do
                    local middle = low + math.floor((high - low) / 2)
                    local value = string.unpack("<I4", data, position + middle * 8)
                    if value < target then low = middle + 1 else high = middle end
                end
                if low < successor_count then
                    local at = position + low * 8
                    if string.unpack("<I4", data, at) == target then
                        return lambda, string.unpack("<f", data, at + 4), true
                    end
                end
                return lambda, 0.0, false
            end
            if context_key > key then
                remember({ missing = true })
                return 1.0, 0.0, false
            end
            position = position + successor_count * 8
        end
        remember({ missing = true })
        return 1.0, 0.0, false
    end

    local function logp(prev2, prev1, target)
        local first = scalar(prev2)
        local second = scalar(prev1)
        local third = scalar(target)
        local unigram = lookup_unigram(third, unknown)
        local bigram_lambda, bigram_probability = lookup_context(
            "b", bi_index, bi_index_count, bi_ctx_count, bi_index_off, second, third)
        local bigram = bigram_probability + bigram_lambda * unigram
        local trigram_lambda, trigram_probability = lookup_context(
            "t", tri_index, tri_index_count, tri_ctx_count, tri_index_off,
            pack2(first, second), third)
        local probability = trigram_probability + trigram_lambda * bigram
        return math.log(math.max(probability, 1e-300))
    end

    local function has_observed_bigram(prev, target)
        local _, _, observed = lookup_context(
            "b", bi_index, bi_index_count, bi_ctx_count, bi_index_off,
            scalar(prev), scalar(target))
        return observed
    end

    return {
        path = path,
        bytes = file_size,
        format = "TCSKNM02",
        resident_index_bytes = #unigrams + #bi_index + #tri_index,
        cache_limit_bytes = MOBILE_CACHE_BYTES,
        logp = logp,
        has_observed_bigram = has_observed_bigram,
        close = function() file:close() end
    }
end

function M.load(path)
    local file = assert(io.open(path, "rb"), "cannot open n-gram: " .. path)
    local magic = file:read(8)
    file:close()
    if magic == "TCSKNM02" then
        return load_mobile(path)
    end
    return load_legacy(path)
end

function M.try_load()
    local failures = {}
    for _, path in ipairs(M.candidate_paths()) do
        if file_exists(path) then
            local ok, model = pcall(M.load, path)
            if ok then
                return model, nil
            end
            failures[#failures + 1] = path .. ": " .. tostring(model)
        end
    end
    if #failures > 0 then
        return nil, table.concat(failures, " | ")
    end
    return nil, "no sentence n-gram model found"
end

return M
