--封装type函数
if rawequal(type(setmetatable({"unifuncex"}, { __type = function(self) return self[1] end })), "unifuncex") then
  -- 如果已经被封装，则导入备用的c包
  rawtype = require "rawtype"
 else
  rawtype = type
  function type(var)
    local _type = rawtype(var)
    local meta = getmetatable(var)
    return meta and meta.__type and meta.__type(var) or _type
  end
end



-- 检查变量通过某函数后的返回值是否符合预期
function checkreturn(func, ...)
  local args = {...}
  local n = #args // 2
  if #args % 2 ~= 0 then
    table.insert(args, "any")
    n = n + 1
  end
  for i = 1, n do
    local success, actual_or_err = pcall(func, args[i])
    local expected = args[i + n]
    if not success then
      return false, i, actual_or_err -- 函数运行错误，返回出错位置与原始错误信息
    end
    if expected ~= "any" and expected ~= actual_or_err then
      return false, i, n -- 不符合预期，返回第一个意外的位置和检查的次数
    end
  end
  return true, n, n -- 符合预期，返回最终位置和检查的次数（两者相等）
end



-- 检查参数类型
local function checkargs(...)
  local result, last, n = checkreturn(...)
  local type = ...
  return result or error("bad argument #" .. last .. " to '" .. debug.getinfo(2, "n").name .. "' (" .. select( 1 + last + n, ...) .. " expected, got " .. type(select( 1 + last, ...)) .. ")", 3)
end



-- 参数类型自动检查器
function ArgTypeAutoChecker(_begin, _end, ...)
  local ignore_b = rawtype(_begin) == "string"
  local ignore_e = rawtype(_end) == "string"
  local info = debug.getinfo(2, "nu")
  local name = info.name or "anonymous function"
  local nparams = info.nparams
  local exception
  if ignore_b then
    exception = ignore_e and error("Invalid argument types") or { _begin, _end, ... }
    _begin, _end = 1, nparams
   elseif ignore_e then
    exception = { _end, ... }
    _end = nparams
   else
    exception = _end <= nparams and { ... } or error("number of parameters out of range")
  end
  for cur_index = _begin, _end do
    local _, arg = debug.getlocal(2, cur_index)
    local arg_type = rawtype(arg)
    local expected_type = exception[cur_index - _begin + 1]
    if arg_type ~= expected_type then
      error("bad argument #" .. cur_index .. " to '" .. name .. "' (" .. expected_type .. " expected, got " .. arg_type .. ")", 3)
    end
  end
end



-- 变成布尔（0是false）
function toboolean(value)
  return value ~= nil and value ~= false and value ~= 0
end



-- 广义异或运算
function xor(x, y)
  local bx = toboolean(x)
  local by = toboolean(y)
  -- 同真同假返回false
  if bx == by then
    return false
  end
  -- 否则返回真的那个值
  return bx and x or y
end



-- 广义同或运算
function xnor(x, y)
  local bx = toboolean(x)
  local by = toboolean(y)
  -- 同真返回原来两个值
  if bx and by then
    return x, y
  end
  -- 同假返回true，一真一假返回false
  return bx == by
end



-- 尝试转为数字
function trytonumber(value)
  return tonumber(value) or value
end



-- 尝试改变数据类型
function string.tryto(str)
  return str == "true" or str ~= "false" and trytonumber(str)
end



-- 获取上层栈的局部变量表
local function get_L(level)
  local _L = {}
  local cur_index = 1
  while true do
    local var_name, var_value = debug.getlocal(level, cur_index)
    if not var_name then break end
    _L[var_name] = var_value
    cur_index = cur_index + 1
  end
  return _L
end



-- 所有的访问等级
-- 访问等级用一个三进制两位数表示，用它的十进制数储存
-- 高位控制局部变量，低位控制全局变量
-- 0代表禁用，1代表只读，2代表可写
-- 只读限定对table中的域无效，table可读域就可写
local exe = {
  -- 01: 局部变量禁用，全局变量只读
  [1] = function(str)
    local env = setmetatable({}, { __index = _G })
    return assert(load(str, str, "t", env))()
  end,
  -- 02: 局部变量禁用，全局变量可写
  [2] = function(str)
    return assert(load(str, str, "t"))()
  end,
  -- 10: 局部变量只读，全局变量禁用
  [3] = function(str)
    local env = get_L(3)
    if env._ENV == _G then env._ENV = nil end
    return assert(load(str, str, "t", env))()
  end,
  -- 11: 局部变量只读，全局变量只读
  [4] = function(str)
    local env = setmetatable(get_L(3), { __index = _G })
    if env._ENV == _G then env._ENV = nil end
    return assert(load(str, str, "t", env))()
  end,
  -- 12: 局部变量只读，全局变量可写
  [5] = function(str)
    local env = get_L(3)
    if env._ENV == _G then env._ENV = nil end
    setmetatable(env, { __index = _G, __newindex = _G })
    return assert(load(str, str, "t", env))()
  end
}



-- 执行文本代码
function execute(str, aces_lv, env)
  if env or rawtype(aces_lv) == "table" then
    -- 只要指定了环境，所有外部变量都禁用
    return assert(load(str, str, "t", env or aces_lv))()
  end
  return exe[aces_lv or 4](str) -- 默认全只读
end



-- 格式化输出
function printf(form, ...)
  print(type(form) == "string" and form:format(...) or tostring(form))
end



-- 执行shell命令并返回shell输出
function shell(command, inTerminal)
  local handle = assert(io.popen(command), "Failed to open pipe for command: "..command)
  local result = handle:read("*a")
  local status = handle:close()
  assert(status, "Failed to close handle after command: "..command)
  return inTerminal and result or result:sub(1, -2)
end



-- 创建多级目录
function mkdirs(path)
  local File = luajava.bindClass "java.io.File"
  path = File(path)
  if not path.exists() then
    mkdirs(path.getParentFile().toString())
    path.mkdir()
  end
end



-- 创建文件（自动新建目录）
function mkfile(path)
  mkdirs(path: match("^(.+)/[^/]+$"))
  io.open(path, "w"): close()
end



-- 列出完整表格
local function tb_to_str(tb, max_depth, indent)
  if rawtype(tb) ~= "table" then
    return tostring(tb)
  end
  indent = indent or 0
  max_depth = max_depth or 10 -- 默认最大递归深度 10
  if indent >= max_depth then
    return "{...}" -- 超过最大深度时省略，防止栈溢出
  end
  local str_list = {}
  local prefix = string.rep("  ", indent)
  for key, value in next, tb do
    local key_str = rawtype(key) == "string" and string.format("[\"%s\"]", key) or string.format("[%s]", tostring(key))
    local value_str = value ~= _G and (value ~= tb and tb_to_str(value, max_depth, indent + 1) or "__self") or "_G" -- 排除_G与自引用，防止栈溢出
    table.insert(str_list, prefix .. key_str .. " = " .. value_str)
  end
  return "{\n" .. table.concat(str_list, ",\n") .. "\n" .. string.rep("  ", indent - 1) .. "}"
end



-- 打印完整表格（支持多个参数）
function printt(...)
  local params = table.pack(...)
  for i = 1, params.n do
    params[i] = tb_to_str(params[i])
  end
  print(table.unpack(params, 1, params.n))
end



-- 打印完整表格（支持指定深度）
function table.print(tb, max_depth)
  print(tb_to_str(tb, max_depth))
end



-- 获取表中元素数量
function table.len(tb)
  local len = 0
  for aaa in next, tb do
    len = len + 1
  end
  return len
end



-- 获取表中最大正整数索引
table.maxn = table.maxn or function(tb)
  checkargs(rawtype, tb, "table")
  local max = 0
  for index in next, tb do
    max = type(index) == "number" and index > max and index == math.floor(index) and index or max
  end
  return max
end



-- 用表2的值覆盖表1
function table.override(tb1, tb2)
  checkargs(rawtype, tb1, tb2, "table", "table")
  for key, value in next, tb2 do
    tb1[key] = value
  end
  return tb1
end



-- 继承所有键值对
function table.inherit(tb)
  return table.override({}, tb)
end



-- 合并table（索引相同的后一个覆盖前一个）
function table.collect(tb1, tb2)
  checkargs(rawtype, tb1, tb2, "table", "table")
  local result = table.inherit(tb1)
  for key, value in next, tb2 do
    result[key] = value
  end
  return result
end



-- 完全复制 table（不继承元表）
function table.copy(tb, seen)
  if rawtype(tb) ~= "table" then
    return tb -- 非 table 类型直接返回自身
  end
  if seen and seen[tb] then
    return seen[tb] -- 处理循环引用
  end
  local new = {}
  seen = seen or {} -- 记录已复制的表，避免重复
  rawset(seen, tb, new)
  for key, value in next, tb do
    rawset(new, key, table.copy(value, seen))
  end
  return new
end



-- 完全复制 table（继承元表）
table.clone = table.clone or function(tb)
  return setmetatable(table.copy(tb), getmetatable(tb))
end



-- 分离table的非数组部分与数组部分
function table.detach(tb)
  local array = {}
  local hash = {}
  for key, value in next, tb do
    if type(key) == "number" and key > 0 and key == math.floor(key) then
      rawset(array, key, value)
     else
      rawset(hash, key, value)
    end
  end
  return hash, array
end