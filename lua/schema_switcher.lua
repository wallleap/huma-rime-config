local M = {}

-- Try to load base library for path resolution
local base
pcall(function()
    base = require("lib.base")
end)

-- Helper to read file content
local function read_file(path)
   local file = io.open(path, "r")
   if not file then return nil end
   local content = file:read("*a")
   file:close()
   return content
end

-- Helper to get schema name from ID
local function get_schema_name(schema_id, rime_dir)
   local name = nil

   -- 1. Try to read from custom.yaml first (patch override)
   if rime_dir then
       local custom_file = rime_dir .. "/" .. schema_id .. ".custom.yaml"
       local custom_content = read_file(custom_file)
       if custom_content then
           -- Try to find patch/schema/name
           name = custom_content:match('schema/name:%s*"([^"]+)"') or custom_content:match('schema/name:%s*([^\n\r]+)')
       end
   end
   
   if name then return name end

   -- 2. Try to use Config if available (most reliable for active config)
   if Config then
      pcall(function()
          local config = Config(schema_id)
          if config then
             name = config:get_string("schema/name")
          end
      end)
      if name then return name end
   end

   -- 3. Fallback: Read schema.yaml directly
   local file_name = schema_id .. ".schema.yaml"
   if rime_dir then
       file_name = rime_dir .. "/" .. file_name
   end
   
   local content = read_file(file_name)
   if not content then return schema_id end
   
   name = content:match('name:%s*"([^"]+)"') or content:match('name:%s*([^\n\r]+)')
   if not name then
      name = content:match('schema/name:%s*"([^"]+)"') or content:match('schema/name:%s*([^\n\r]+)')
   end
   return name or schema_id
end

-- Cache for schema list
local schemas_cache = nil
local id_name_map = {} -- Map name -> id for reverse lookup

local function load_schemas(env)
   if schemas_cache then return end
   schemas_cache = {}
   id_name_map = {}
   
   local rime_dir = "."
   if base and base.get_rime_dir then
       rime_dir = base.get_rime_dir()
   end
   
   -- Read default.custom.yaml
   local file_path = rime_dir .. "/default.custom.yaml"
   local content = read_file(file_path)
   
   if not content then
      -- Fallback: try default.yaml
      file_path = rime_dir .. "/default.yaml"
      content = read_file(file_path)
   end
   
   if not content then
       -- Last resort: try relative path if rime_dir failed
       content = read_file("default.custom.yaml") or read_file("default.yaml")
   end
   
   if not content then 
       return 
   end
   
   -- Extract schema_list
   for schema_id in content:gmatch("- schema:%s*([%w_]+)") do
      local name = get_schema_name(schema_id, rime_dir)
      table.insert(schemas_cache, {id = schema_id, name = name})
      id_name_map[name] = schema_id
   end
end

function M.init(env)
   load_schemas(env)
   
   local context = env.engine.context
   
   -- Track selected candidate
   if context.select_notifier then
       env.select_conn = context.select_notifier:connect(function(ctx)
           local cand = ctx:get_selected_candidate()
           if cand then
               -- Try to identify if it is a switcher candidate
               local genuine = cand
               if cand.get_genuine then genuine = cand:get_genuine() end
               
               if genuine.type:find("^schema_switch:") then
                   env.selected_switcher_id = genuine.type:sub(15)
               elseif cand.type:find("^schema_switch:") then
                   env.selected_switcher_id = cand.type:sub(15)
               else
                   -- Fallback: check by name
                   local text = cand.text:gsub(" 👈", "")
                   if id_name_map[text] then
                       env.selected_switcher_id = id_name_map[text]
                   else
                       env.selected_switcher_id = nil
                   end
               end
           else
               env.selected_switcher_id = nil
           end
       end)
   end
   
   -- Handle commit event (for mouse clicks / touch input)
   if context.commit_notifier then
       env.commit_conn = context.commit_notifier:connect(function(ctx)
           if ctx.input == "mode" and env.selected_switcher_id then
               -- A commit happened in mode switching context, and we have a valid switcher target
               local target_id = env.selected_switcher_id
               local engine = env.engine
               
               -- Try to delete the committed text (best effort)
               -- Note: delete_surrounding_text is not always supported or available in all contexts
               if context.delete_surrounding_text then
                   -- Assuming length of committed text matches candidate text length
                   -- Since we can't easily know exact length here, we skip or try conservative delete
                   -- context:delete_surrounding_text(2, 0) -- Example: delete 2 chars
               end
               
               -- Logic duplicated from apply_switch
               local final_target_id = target_id
               local current_id = engine.schema.schema_id
               
               if target_id == current_id then
                   if not schemas_cache then load_schemas(env) end
                   if schemas_cache and #schemas_cache > 0 then
                       local current_idx = 0
                       for i, item in ipairs(schemas_cache) do
                           if item.id == current_id then
                               current_idx = i
                               break
                           end
                       end
                       if current_idx > 0 then
                           local next_idx = (current_idx % #schemas_cache) + 1
                           final_target_id = schemas_cache[next_idx].id
                       elseif #schemas_cache > 0 then
                           final_target_id = schemas_cache[1].id
                       end
                   end
               end
               
               engine:apply_schema(Schema(final_target_id))
               -- Context clear is usually automatic after commit, but apply_schema resets it anyway
           end
       end)
   end
end

function M.fini(env)
    if env.select_conn then env.select_conn:disconnect() end
    if env.commit_conn then env.commit_conn:disconnect() end
end

function M.translator(input, seg, env)
   if input ~= "mode" then return end
   
   load_schemas(env)
   
   if not schemas_cache or #schemas_cache == 0 then 
       local cand = Candidate("schema_switch:error", seg.start, seg._end, "配置读取失败", "无法找到方案列表")
       yield(cand)
       return 
   end
   
   local current_id = env.engine.schema.schema_id
   
   -- Reorder: current first
   local sorted_list = {}
   local current_item = nil
   
   for _, item in ipairs(schemas_cache) do
      if item.id == current_id then
         current_item = item
      else
         table.insert(sorted_list, item)
      end
   end
   
   if current_item then
      table.insert(sorted_list, 1, current_item)
   end
   
   -- Yield candidates
   for i, item in ipairs(sorted_list) do
      local text = item.name
      local comment = "（切换方案）"
      if item.id == current_id then
         text = text .. " 👈"
      end
      
      -- Use type to store ID: "schema_switch:ID"
      local cand = Candidate("schema_switch:" .. item.id, seg.start, seg._end, text, comment)
      cand.quality = 1000 -- High quality
      yield(cand)
   end
end

-- Filter to clean up comments for schema switch candidates
function M.filter(input, env)
    -- If we are not in mode switch, just pass through
    local context = env.engine.context
    if context.input ~= "mode" then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    if not schemas_cache then load_schemas(env) end

    for cand in input:iter() do
        -- Check if it's our candidate or if it matches a schema name
        local is_switcher = false
        local genuine = cand
        if cand.get_genuine then
            genuine = cand:get_genuine()
        end
        
        if genuine.type:find("^schema_switch:") then
            is_switcher = true
        elseif cand.type:find("^schema_switch:") then
            is_switcher = true
        else
            -- Fallback check by name
            local text = cand.text:gsub(" 👈", "")
            if id_name_map[text] then
                is_switcher = true
            end
        end

        if is_switcher then
            -- Reset comment to remove any "chaifen" or other noise
            -- Create a new candidate to strip away any attached shadow candidate properties
            local type_str = genuine.type
            if not type_str:find("^schema_switch:") then
                -- Try to recover type from name if possible, or default to generic
                local text = cand.text:gsub(" 👈", "")
                if id_name_map[text] then
                    type_str = "schema_switch:" .. id_name_map[text]
                else
                    type_str = "schema_switch:unknown"
                end
            end
            
            local comment = "（切换方案）"
            if cand.text:find(" 👈") then
                comment = ""
            end
            
            local new_cand = Candidate(type_str, cand.start, cand._end, cand.text, comment)
            new_cand.quality = cand.quality
            new_cand.preedit = cand.preedit
            yield(new_cand)
        else
            yield(cand)
        end
    end
end

function M.processor(key, env)
   local engine = env.engine
   local context = engine.context
   
   local function apply_switch(target_id)
       local final_target_id = target_id
       local current_id = engine.schema.schema_id

       -- If selected schema is the current one, cycle to the next one in the list
       if target_id == current_id then
           if not schemas_cache then load_schemas(env) end
           if schemas_cache and #schemas_cache > 0 then
               local current_idx = 0
               for i, item in ipairs(schemas_cache) do
                   if item.id == current_id then
                       current_idx = i
                       break
                   end
               end
               
               if current_idx > 0 then
                   local next_idx = (current_idx % #schemas_cache) + 1
                   final_target_id = schemas_cache[next_idx].id
               elseif #schemas_cache > 0 then
                   final_target_id = schemas_cache[1].id
               end
           end
       end
       
       engine:apply_schema(Schema(final_target_id))
       context:clear()
   end
   
   if not context:has_menu() then return 2 end -- kNoop
   
   if context.input ~= "mode" then return 2 end
   
   local selected = context:get_selected_candidate()
   local schema_id_to_switch = nil
   
   -- Strategy 1: Check candidate type (Ideal)
   if selected then
       local genuine = selected
       if selected.get_genuine then
           genuine = selected:get_genuine()
       end
       
       if genuine.type:find("^schema_switch:") then
           local id = genuine.type:sub(15)
           if id ~= "error" then
               schema_id_to_switch = id
           end
       elseif selected.type:find("^schema_switch:") then
           local id = selected.type:sub(15)
           if id ~= "error" then
               schema_id_to_switch = id
           end
       end
   end
   
   -- Strategy 2: Fallback - Check candidate text against known schema names
   if not schema_id_to_switch and selected then
       local text = selected.text:gsub(" 👈", "")
       if id_name_map[text] then
           schema_id_to_switch = id_name_map[text]
       end
   end
   
   local keycode = key.keycode
   local is_confirm = (keycode == 32 or keycode == 65293 or keycode == 65421)
   
   if schema_id_to_switch and is_confirm then
       apply_switch(schema_id_to_switch)
       return 1 -- kAccepted
   end
   
   -- Handle number keys (1-9)
   if keycode >= 49 and keycode <= 57 then
       local idx = keycode - 49
       local composition = context.composition
       if not composition:empty() then
           local seg = composition:back()
           
           local page_size = engine.schema.page_size or 5
           if engine.schema.config then
               page_size = engine.schema.config:get_int("menu/page_size") or 5
           end
           
           local selected_index = seg.selected_index
           local page_start = math.floor(selected_index / page_size) * page_size
           local target_index = page_start + idx
           
           if not schemas_cache then load_schemas(env) end
           if schemas_cache and #schemas_cache > 0 then
               local current_id = engine.schema.schema_id
               local sorted_list = {}
               local current_item = nil
               for _, item in ipairs(schemas_cache) do
                  if item.id == current_id then current_item = item else table.insert(sorted_list, item) end
               end
               if current_item then table.insert(sorted_list, 1, current_item) end
               
               local item = sorted_list[target_index + 1]
               if item then
                   apply_switch(item.id)
                   return 1 -- kAccepted
               end
           end
       end
   end
   
   return 2 -- kNoop
end

return M
