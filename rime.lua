charset_comment_filter = require("charset_comment_filter") --Unicode分区提示
core2022 = require("core2022_filter")                      --自定义字符集过滤（常用字集）
-- dz_ci = require("dz_ci_filter") --单字模式 这个别用，有问题的
number_translator = require("number")
lua_unicode_display_filter = require("unicode_display")  --Unicode编码提示
calculator_translator = require("calculator_translator") --简易计算器
exe_processor = require("exe")                           -- 网页启动器

-- 手动造词（默认分隔符为 '）
maker = require("maker")
maker_processor = maker.processor
maker_translator = maker.translator
maker_filter = maker.filter

-- 自定义方案切换器（默认关键词为 mode）
local schema_switcher = require("schema_switcher")
switcher_processor = { init = schema_switcher.init, func = schema_switcher.processor }
switcher_translator = schema_switcher.translator
switcher_filter = schema_switcher.filter

-- 拆分滤镜（追加模式）
chaifen_comment_filter = require("chaifen_comment_filter")
