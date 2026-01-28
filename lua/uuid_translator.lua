-- uuid_translator.lua
-- 用于 Rime 输入法，输入特定关键字生成 UUID
-- 在方案中的 engine/translators 添加 - lua_translator@*uuid_translator # UUID 输入

local function generate_uuid()
  local random = math.random
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and random(0, 15) or random(8, 11)
    return string.format('%x', v)
  end)
end

-- Translator: 当输入 "uuid" 时，候选栏出现一个 uuid
function uuid_translator(input, seg)
  if input == "uuid" then
    yield(Candidate("uuid", seg.start, seg._end, generate_uuid(), "UUID"))
  end
end

return uuid_translator
