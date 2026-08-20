local M = {}

-- 初始化特殊 tag 集合：从 recognizer/patterns 动态读取所有 tag 名（排除反查 tag）
-- 缓存到 env.special_tags，避免每次过滤都读 config
function M.init_special_tags(env)
  env.special_tags = {}
  local config = env.engine.schema.config
  local map = config:get_map("recognizer/patterns")
  if map then
    for _, tag in pairs(map:keys()) do
      if tag ~= "reverse_lookup" and tag ~= "flypy_lookup" then
        env.special_tags[tag] = true
      end
    end
  end
  -- switcher（mode）切换方案的候选也不追加注释
  env.special_tags[config:get_string("switcher/tag") or "mode"] = true
end

-- 检查 segment 是否为反查（reverse_lookup 或 flypy_lookup）
function M.is_reverse_segment(seg)
  return seg and (seg:has_tag("reverse_lookup") or seg:has_tag("flypy_lookup")) or false
end

-- 检查 segment 是否带有特殊 tag（recognizer 匹配的特殊功能或切换方案）
function M.is_special_segment(seg, env)
  if not seg or not env.special_tags then return false end
  for tag in pairs(env.special_tags) do
    if seg:has_tag(tag) then return true end
  end
  return false
end

return M
