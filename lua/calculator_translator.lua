-- 计算器插件
-- author: https://github.com/ChaosAlphard
-- contributor: https://github.com/DeepChirp
local calculator_translator = {}

function calculator_translator.init(env)
  local config = env.engine.schema.config
  env.prefix = config:get_string('calculator/prefix') or '='
  env.show_prefix = config:get_bool('calculator/show_prefix') -- set to true to show prefix in preedit area
end

local function truncateFromStart(str, truncateStr) return string.sub(str, string.len(truncateStr) + 1) end

local function yield_calc_cand(seg, cand_text, cand_comment, cand_preedit, show_prefix)
  local cand = Candidate('calc', seg.start, seg._end, cand_text, cand_comment)
  cand.quality = 99999
  if not show_prefix then cand.preedit = cand_preedit end
  yield(cand)
end

-- ==================== 需要额外逻辑的函数 ====================

-- random([m [,n]]) 返回 m-n 之间的随机数, n 为空则返回 1-m 之间, 都为空则返回 0-1 之间的小数
-- 直接复用 math.random

-- frexp(x) 返回 m,e 使得 x = m * 2^e; 由于是两个返回值, 无法参与后续运算, 以字符串形式展示
local function frexp(x)
  local m, e = math.frexp(x)
  return m .. ' * 2^' .. e
end

-- 返回 x^y
local function pow(x, y) return x ^ y end

-- y 为底 x 的对数, 使用换底公式实现
local function log(y, x)
  -- 底数和真数不能为负数或 0
  if x <= 0 or y <= 0 then return nil end
  return math.log(x) / math.log(y)
end

-- e 为底 x 的对数
local function loge(x)
  -- 真数不能为负数或 0
  if x <= 0 then return nil end
  return math.log(x)
end

-- 10 为底 x 的对数
local function log10(x)
  -- 真数不能为负数或 0
  if x <= 0 then return nil end
  return math.log10(x)
end

-- atan2(y, x) 返回以弧度为单位的点 (x, y) 相对于 x 轴的逆时针角度, 范围从 -π 到 π
-- 相比 math.atan(y/x) 能正确处理 x=0 等边界情况
-- Lua 5.4 已移除 math.atan2, 需用双参 math.atan 兼容
local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- 求和, 返回 (总和, 样本数量)
local function sum(...)
  local n = select('#', ...)
  local total = 0
  for i = 1, n do total = total + select(i, ...) end
  return total, n
end

-- 平均值
local function avg(...)
  local total, n = sum(...)
  -- 样本数量不能为 0
  if n == 0 then return nil end
  return total / n
end

-- 方差 (总体方差, 除以 n)
local function variance(...)
  local total, n = sum(...)
  -- 样本数量不能为 0
  if n == 0 then return nil end
  local mean = total / n

  -- 计算离差平方和
  local sum_squared_diff = 0
  for i = 1, n do
    local v = select(i, ...)
    sum_squared_diff = sum_squared_diff + (v - mean) ^ 2
  end
  return sum_squared_diff / n
end

-- 阶乘
local function factorial(x)
  -- 不能为负数
  if x < 0 then return nil end
  if x == 0 or x == 1 then return 1 end

  local result = 1
  for i = 1, x do result = result * i end
  return result
end

-- 四舍五入
local function round(x) return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5) end

-- 取模
local function mod(x, y) return x % y end

-- ==================== 函数注册表 ====================
-- 每个条目: { 名称, 实现, 示例, 描述 }
-- 常量与函数统一注册, 注册表同时驱动帮助提示, 避免两份维护
local definitions = {
  -- 常量
  { 'pi', math.pi, 'pi', '圆周率 π' },
  { 'e', math.exp(1), 'e', '自然对数底 e' },
  -- 三角函数 (弧度)
  { 'sin', math.sin, 'sin(x)', '正弦 (弧度)' },
  { 'cos', math.cos, 'cos(x)', '余弦 (弧度)' },
  { 'tan', math.tan, 'tan(x)', '正切 (弧度)' },
  { 'asin', math.asin, 'asin(x)', '反正弦' },
  { 'acos', math.acos, 'acos(x)', '反余弦' },
  { 'atan', math.atan, 'atan(x)', '反正切' },
  { 'atan2', atan2, 'atan2(y, x)', '反正切 (y, x 分量)' },
  { 'sinh', math.sinh, 'sinh(x)', '双曲正弦' },
  { 'cosh', math.cosh, 'cosh(x)', '双曲余弦' },
  { 'tanh', math.tanh, 'tanh(x)', '双曲正切' },
  -- 指数、对数与幂
  { 'exp', math.exp, 'exp(x)', 'e的x次幂' },
  { 'sqrt', math.sqrt, 'sqrt(x)', '平方根' },
  { 'pow', pow, 'pow(x, y)', 'x的y次幂 (x^y)' },
  { 'log', log, 'log(base, x)', '以 base 为底 x 的对数' },
  { 'loge', loge, 'loge(x)', '自然对数' },
  { 'log10', log10, 'log10(x)', '以10为底对数' },
  { 'ldexp', math.ldexp, 'ldexp(x, y)', 'x * 2^y' },
  { 'frexp', frexp, 'frexp(x)', 'x = m * 2^e 分解' },
  -- 取整、绝对值与最值
  { 'floor', math.floor, 'floor(x)', '向下取整' },
  { 'ceil', math.ceil, 'ceil(x)', '向上取整' },
  { 'round', round, 'round(x)', '四舍五入' },
  { 'abs', math.abs, 'abs(x)', '绝对值' },
  { 'min', math.min, 'min(a, b, ...)', '最小值' },
  { 'max', math.max, 'max(a, b, ...)', '最大值' },
  { 'mod', mod, 'mod(x, y)', '取模 (x % y)' },
  -- 角度换算
  { 'deg', math.deg, 'deg(rad)', '弧度转角度' },
  { 'rad', math.rad, 'rad(deg)', '角度转弧度' },
  -- 其他
  { 'fact', factorial, 'fact(n) or n!', '阶乘' },
  { 'random', math.random, 'random(m, n)', '随机数' },
  { 'rdm', math.random, 'random(m, n)', '随机数' },
  { 'avg', avg, 'avg(1, 2, ...)', '平均值' },
  { 'var', variance, 'var(1, 2, ...)', '方差' },
}

-- 函数表, 同时作为表达式求值时的全局环境
local calcPlugin = {}
-- 帮助信息, 由注册表生成
local help_map = {}
for _, def in ipairs(definitions) do
  local name, fn, demo, desc = def[1], def[2], def[3], def[4]
  calcPlugin[name] = fn
  help_map[#help_map + 1] = { cmd = name, demo = demo, desc = desc }
end

-- ==================== 表达式预处理 ====================

-- 实现阶乘计算(!)
local function replaceToFactorial(str)
  -- 替换 [0-9]! 字符为 fact([0-9]) 以实现阶乘
  return str:gsub('([0-9]+)!', 'fact(%1)')
end

-- 处理百分号
local function replacePercent(str)
  str = str .. ' '
  -- 先处理括号形式 ( ... )%
  str = str:gsub('(%b())%%(%D)', function(block, tail)
    return '(' .. block .. '/100)' .. tail
  end)
  -- 再处理纯数字形式 123% 12.3%
  str = str:gsub('(%d+%.?%d*)%%(%D)', function(num, tail)
    return '(' .. num .. '/100)' .. tail
  end)
  return str:sub(1, -2)
end

-- 截断错误信息, 避免提示过长
local function shortErr(err) return string.sub(tostring(err), 1, 40) end

-- ==================== 简单计算器 ====================

function calculator_translator.func(input, seg, env)
  if not seg:has_tag('expression') or input == '' then return end

  local composition = env.engine.context.composition
  local segment = composition:back()

  -- 提取算式
  local express = truncateFromStart(input, env.prefix)
  if express == '' then
    segment.prompt = '算式示例：1+1、sin(pi)'
    return
  end

  local code = replacePercent(replaceToFactorial(express))
  -- 先编译再执行, 以便区分语法错误与运行错误
  local chunk, load_err = load('return ' .. code, 'calculate', 't', calcPlugin)
  local result, err_msg
  if chunk then
    local ok, res = pcall(chunk)
    if ok then result = res else err_msg = res end
  else
    err_msg = load_err
  end

  if result ~= nil and (type(result) == 'string' or type(result) == 'number') and #tostring(result) > 0 then
    yield_calc_cand(seg, result, '', express, env.show_prefix)
    yield_calc_cand(seg, express .. '=' .. result, '', express, env.show_prefix)
    return
  end

  -- 计算失败: 先尝试匹配帮助信息 (输入函数名或其前缀时给出用法提示)
  local lower_express = string.lower(express)
  for _, info in ipairs(help_map) do
    if string.find(string.lower(info.cmd), lower_express, 1, true) == 1 then
      segment.prompt = info.demo .. '  ' .. info.desc
      return
    end
  end

  -- 帮助也未命中, 给出具体失败原因
  segment.prompt = err_msg and ('解析失败: ' .. shortErr(err_msg)) or '解析失败'
end

return calculator_translator
