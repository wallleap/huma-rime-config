-- 变量定义
local rv_var = {
  switch_schema = "mode",
}

-- 跨平台路径分隔符
local path_sep = package.config:sub(1, 1)

local kRejected = 0
local kAccepted = 1
local kNoop = 2

local function get_schema_name(schema_id)
  local user_data_dir = rime_api.get_user_data_dir() -- 获取用户目录路径

  local function read_name(path)
    local file = io.open(path, "rb")
    if file then
      for line in file:lines() do
        local m, n = line:match("(%s*name%:%s)%s*%p*([^%c%s]+)%p*")
        if m and n then
          file:close()
          return n:gsub("[']+$", ""):gsub('["]+$', '')
        end
      end
      file:close()
    end
    return nil
  end

  -- 先尝试 custom.yaml
  local custom_name = read_name(user_data_dir .. path_sep .. schema_id .. ".custom.yaml")
  if custom_name then return custom_name end

  -- 再尝试 schema.yaml
  local schema_name = read_name(user_data_dir .. path_sep .. schema_id .. ".schema.yaml")
  if schema_name then return schema_name end

  return ""
end

local function get_schema_list()
  local user_data_dir = rime_api.get_user_data_dir()
  user_data_dir = user_data_dir .. path_sep .. "build" .. path_sep .. "default.yaml"
  local file = io.open(user_data_dir, "rb")
  if file then
    local schema_list = {}
    for line in file:lines() do
      local m, n = line:match("(%-%s*schema%:%s)([^%c%s]+)")
      if m and n then
        local name = get_schema_name(n)
        if name ~= "" then table.insert(schema_list, { n, name }) end
      end
    end
    file:close()
    return schema_list
  end
end

local enable_schema_list = get_schema_list()

-- 帮助函数，返回被选中的候选的索引
local function select_index(key, env)
  local ch = key.keycode
  local index = -1
  local select_keys = env.engine.schema.select_keys

  if select_keys ~= nil and select_keys ~= "" and not key.ctrl() and ch >= 0x20 and ch < 0x7f then
    local pos = string.find(select_keys, string.char(ch))
    if pos ~= nil then index = pos end
  elseif ch >= 0x30 and ch <= 0x39 then
    index = (ch - 0x30 + 9) % 10
  elseif ch >= 0xffb0 and ch < 0xffb9 then
    index = (ch - 0xffb0 + 9) % 10
  elseif ch == 0x20 then
    index = 0
  end
  return index
end

local function IsExistChar(obj, chars)
  if type(obj) ~= "table" or chars == "" then return "" end
  for i = 1, #obj do
    if obj[i][2] == chars then return obj[i][1] end
  end
  return ""
end

local function selector(key, env)
  if env.switcher == nil then return kNoop end
  if key:release() or key:alt() then return kNoop end
  local context = env.engine.context
  if (context:is_composing()) then
    local idx = select_index(key, env)
    if idx < 0 then return kNoop end
    local composition = context.composition
    local segment = composition:back()
    -- 新增：检查segment是否存在（避免segment为nil）
    if not segment then return kNoop end

    local codetext = env.engine.context.input
    local schema_name = env.engine.schema.schema_name or ""
    local candidate_count = segment.menu:candidate_count()
    -- 修正1：将 `or ""` 改为 `or {}`（确保selected_candidate为表）
    local selected_candidate = segment:get_selected_candidate() or {}
    local page_pos = math.modf(segment.selected_index / page_size) + 1

    -- 修正2：安全访问text字段（避免nil）
    local last_candidate = selected_candidate.text or ""

    if page_pos > 1 then
      idx = (page_pos - 1) * page_size + idx
    end

    if candidate_count then
      -- 原逻辑：若通过数字键选择候选，更新last_candidate
      if key.keycode > 0x2f and key.keycode < 0x6a and idx > -1 then
        -- 新增：检查候选是否存在（避免越界）
        local candidate = segment:get_candidate_at(idx)
        last_candidate = candidate and candidate.text or ""
      end

      -- 关键字切换逻辑（保持原逻辑，修正字段访问）
      if context.input == rv_var.switch_schema and last_candidate then
        local sc_id = IsExistChar(enable_schema_list, last_candidate)
        if sc_id and sc_id:find("%a") then
          env.engine:apply_schema(Schema(sc_id))
          return kAccepted
        end
      end
    end
  end
  return kNoop
end

-- 初始化
local function init(env)
  if Switcher == nil then return end
  env.switcher = Switcher(env.engine)
  page_size = env.engine.schema.page_size
end

local function set_switch_keywords(input, seg, env)
  local schema_id = env.engine.schema.schema_id or ""
  local composition = env.engine.context.composition
  local segment = composition:back()

  if input == rv_var.switch_schema and #enable_schema_list > 0 then
    -- 修改 segment 的 tag，避免被拆分滤镜处理
    if Set then
      segment.tags = Set({ rv_var.switch_schema })
    end

    local select_index = 1
    for i = 1, #enable_schema_list do
      if enable_schema_list[i][2] then
        local comment = "（切换方案）"
        if enable_schema_list[i][1] == schema_id then
          comment = "  👈"
          select_index = i - 1
        end
        local candidate = Candidate(input, seg.start, seg._end, enable_schema_list[i][2], comment)
        candidate.type = rv_var.switch_schema
        segment.selected_index = select_index
        candidate.quality = 100000000
        yield(candidate)
      end
    end
  end
end

-- Translator
local function translator(input, seg, env)
  set_switch_keywords(input, seg, env)
end

-- Filter: 清理注释
local function filter(input, env)
  local context = env.engine.context
  local schema_id = env.engine.schema.schema_id

  if context.input == rv_var.switch_schema then
    for cand in input:iter() do
      -- 获取真实候选以检查类型
      local genuine = cand:get_genuine()

      -- 仅处理 type 为 mode 的候选 (检查 genuine.type)
      if genuine.type == rv_var.switch_schema then
        -- 使用 genuine.text 匹配，避免 filter 修改了 text
        local id = IsExistChar(enable_schema_list, genuine.text)
        if id then
          if id == schema_id then
            cand.comment = "  👈"
            genuine.comment = "  👈"
          else
            cand.comment = "（切换方案）"
            genuine.comment = "（切换方案）"
          end
        end
      end
      yield(cand)
    end
  else
    for cand in input:iter() do
      yield(cand)
    end
  end
end

return { init = init, processor = selector, translator = translator, filter = filter }
