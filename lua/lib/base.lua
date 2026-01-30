local M = {}

-- 获取 Rime 用户目录
function M.get_rime_dir()
    -- 方式1：尝试使用 rime_api 标准接口 (如果有)
    if rime_api and rime_api.get_user_data_dir then
        return rime_api.get_user_data_dir()
    end
    
    -- 方式2：根据当前脚本文件的位置推断
    -- 假设 base.lua 位于 <UserDir>/lua/lib/base.lua
    local info = debug.getinfo(1, "S")
    local path = info.source
    if path:sub(1, 1) == "@" then
        path = path:sub(2)
    end
    
    -- 统一使用正斜杠
    path = path:gsub("\\", "/")
    
    -- 截取路径：移除 /lua/lib/base.lua
    local dir = path:match("^(.*)/lua/lib/base%.lua$")
    if dir then
        return dir
    end
    
    -- 如果匹配失败，尝试回退三层 (base.lua -> lib -> lua -> UserDir)
    local parent = path:match("^(.*)/[^/]+/[^/]+/[^/]+$")
    if parent then
        return parent
    end

    return "."
end

return M
