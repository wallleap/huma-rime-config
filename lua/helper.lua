-- helper.lua
-- List features and usage of the schema.
local rv_var = { helper = 'help' }

local function translator(input, seg, env)
  local composition = env.engine.context.composition
  local segment = composition:back()
  if input == rv_var.helper then
    -- 修改 segment 的 tag，避免被拆分滤镜处理
    if Set then segment.tags = Set({ rv_var.helper }) end
    local table = {
      {
        '时间输出',
        '→ /date | /time | /week | /month | /datetime | /timestamp | /fjq'
      }, { '其他符号', '→ /fh 等' }, { 'UUID', '→ uuid' },
      { '方案切换', '→ mode' },
      { '金额大写', '→ 大写字母 S 引导+数字' },
      { '反查', '→ `键引导输入对应双拼/笔画' },
      { '选单', '→ Ctrl+` 或 F4' }, { '帮助', '→ help' }
    }
    segment.prompt = '简要说明'
    for k, v in ipairs(table) do
      local cand = Candidate(rv_var.helper, seg.start, seg._end, v[1], ' ' .. v[2])
      cand.type = rv_var.helper
      -- cand.preedit = input .. '\t简要说明'
      -- cand.quality=100000000
      yield(cand)
    end
  end
end

return translator
