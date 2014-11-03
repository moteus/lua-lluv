local function split(str, sep, plain)
  local b, res = 1, {}
  while b <= #str do
    local e, e2 = string.find(str, sep, b, plain)
    if e then
      res[#res + 1] = string.sub(str, b, e-1)
      b = e2 + 1
    else
      res[#res + 1] = string.sub(str, b)
      break
    end
  end
  return res
end

local unpack = unpack or table.unpack

local function usplit(...) return unpack(split(...)) end

local function split_first(str, sep, plain)
  local e, e2 = string.find(str, sep, nil, plain)
  if e then
    return string.sub(str, 1, e - 1), string.sub(str, e2 + 1)
  end
  return str
end

local function slit_first_self_test()
  local s1, s2 = split_first("ab|cd", "|", true)
  assert(s1 == "ab")
  assert(s2 == "cd")

  local s1, s2 = split_first("|abcd", "|", true)
  assert(s1 == "")
  assert(s2 == "abcd")

  local s1, s2 = split_first("abcd|", "|", true)
  assert(s1 == "abcd")
  assert(s2 == "")

  local s1, s2 = split_first("abcd", "|", true)
  assert(s1 == "abcd")
  assert(s2 == nil)
end

local function class(base)
  local t = base and setmetatable({}, base) or {}
  t.__index = t
  t.__base  = base

  function t.new(...)
    local o = setmetatable({}, t)
    if o.__init then
      if t == ... then -- we call as Class:new()
        return o:__init(select(2, ...))
      else             -- we call as Class.new()
        return o:__init(...)
      end
    end
    return o
  end

  return t
end

local function class_self_test()
  local A = class()
  function A:__init(a, b)
    assert(a == 1)
    assert(b == 2)
  end

  A:new(1, 2)
  A.new(1, 2)

  local B = class(A)

  function B:__init(a,b,c)
    assert(self.__base == A)
    A.__init(B, a, b)
    assert(c == 3)
  end

  B:new(1, 2, 3)
  B.new(1, 2, 3)
end

-------------------------------------------------------------------
local Buffer = class() do

function Buffer:__init(eol)
  self._eol = eol or "\n"
  self._tail = ""
  return self
end

function Buffer:next_line(data, eol)
  data = data and (self._tail .. data) or self._tail

  local s1, s2 = split_first(data, eol or self._eol, true)
  if s2 then
    self._tail = s2
    return s1
  end
  self._tail = data
end

function Buffer:next_n(data, n)
  data = data and (self._tail .. data) or self._tail
  if n > #data then
    self._tail = data
    return nil
  end

  local res = string.sub(data, 1, n)
  self._tail = string.sub(data, n+1)
  return res
end

function Buffer:reset()
  self._tail = ""
end

function Buffer:append(data)
  self._tail = self._tail .. data
end

function Buffer:eol()
  return self._eol
end

function Buffer.self_test(EOL)
  local b = Buffer:new(EOL)
  local eol = b:eol()

    -- test next_xxx
  assert("aaa" == b:next_line("aaa" .. eol .. "bbb"))
  assert("bbb" == b._tail, b._tail)

  assert("bbbccc" == b:next_line("ccc" .. eol .. "ddd" .. eol))
  assert("ddd"..eol == b._tail, b._tail)

  assert("ddd" == b:next_line(eol))
  assert(eol == b._tail, "'" .. b._tail .."'")

  assert("" == b:next_line(""))
  assert("" == b._tail, "'" .. b._tail .."'")

  assert(nil == b:next_line(""))
  assert("" == b._tail, "'" .. b._tail .."'")

  assert(nil == b:next_line("aaa"))
  assert("aaa" == b._tail, "'" .. b._tail .."'")

  assert("aaa" == b:next_n("123456", 3))
  assert("123456" == b._tail, "'" .. b._tail .."'")

  assert(nil == b:next_n("", 8))
  assert("123456" == b._tail, "'" .. b._tail .."'")

  assert("123"== b:next_n("", 3))
  assert("456" == b._tail, "'" .. b._tail .."'")

  assert("456" == b:next_n(nil, 3))
  assert("" == b._tail, "'" .. b._tail .."'")

  b:reset()

  assert(nil == b:next_line("aaa|bbb"))
  assert("aaa|bbb" == b._tail, b._tail)

  assert("aaa" == b:next_line(nil, "|"))
  assert("bbb" == b._tail, b._tail)

  b:reset()
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local List = class() do

function List:reset()
  self._first = 0
  self._last  = -1
  self._t     = {}
  return self
end

List.__init = List.reset

function List:push_front(v)
  assert(v ~= nil)
  local first = self._first - 1
  self._first, self._t[first] = first, v
  return self
end

function List:push_back(v)
  assert(v ~= nil)
  local last = self._last + 1
  self._last, self._t[last] = last, v
  return self
end

function List:peek_front()
  return self._t[self._first]
end

function List:peek_back()
  return self._t[self._last]
end

function List:pop_front()
  local first = self._first
  if first > self._last then return end

  local value = self._t[first]
  self._first, self._t[first] = first + 1

  return value
end

function List:pop_back()
  local last = self._last
  if self._first > last then return end

  local value = self._t[last]
  self._last, self._t[last] = last - 1

  return value
end

function List:size()
  return self._last - self._first + 1
end

function List:empty()
  return self._first > self._last
end

function List.self_test()
  local q = List:new()

  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(q:push_back(1) == q)
  assert(q:empty() == false)
  assert(q:size()  == 1)

  assert(q:peek_back() == 1)
  assert(q:empty() == false)
  assert(q:size()  == 1)

  assert(q:peek_front() == 1)
  assert(q:empty() == false)
  assert(q:size()  == 1)

  assert(q:pop_back() == 1)
  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(q:push_front(1) == q)
  assert(q:empty() == false)
  assert(q:size()  == 1)

  assert(q:pop_front() == 1)
  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(q:pop_back() == nil)
  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(q:pop_front() == nil)
  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(false == pcall(q.push_back, q))
  assert(q:empty() == true)
  assert(q:size()  == 0)

  assert(false == pcall(q.push_front, q))
  assert(q:empty() == true)
  assert(q:size()  == 0)

  q:push_back(1):push_back(2)
  assert(q:pop_back() == 2)
  assert(q:pop_back() == 1)

  q:push_back(1):push_back(2)
  assert(q:pop_front() == 1)
  assert(q:pop_front() == 2)
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local Queue = class() do

function Queue:__init()
  self._q = List.new()
  return self
end

function Queue:reset()        self._q:reset()      return self end

function Queue:push(v)        self._q:push_back(v) return self end

function Queue:pop()   return self._q:pop_front()              end

function Queue:peek()  return self._q:peek_front()             end

function Queue:size()  return self._q:size()                   end

function Queue:empty() return self._q:empty()                  end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local Buffer = class() do

function Buffer:__init(eol)
  self._eol = assert(eol)
  self._lst = List.new()
  return self
end

function Buffer:reset()
  self._lst:reset()
  return self
end

function Buffer:eol()
  return self._eol
end

function Buffer:append(data)
  self._lst:push_back(data)
  return self
end

function Buffer:next_line(data, eol)
  eol = eol or self._eol or "\n"
  if data then self:append(data) end
  local lst = self._lst

  local t = {}
  while true do
    local data = lst:pop_front()

    if not data then -- no EOL in buffer
      if #t > 0 then lst:push_front(table.concat(t)) end
      return
    end

    local line, tail = split_first(data, eol, true)
    t[#t + 1] = line
    if tail then -- we found EOL
      lst:push_front(tail)
      return table.concat(t)
    end
  end
end

function Buffer:next_n(data, n)
  if data then self:append(data) end
  if n == 0 then
    if self._lst:empty() then return end
    return ""
  end

  local lst = self._lst
  local size, t = 0, {}

  while true do
    local chunk = lst:pop_front()

    if not chunk then -- buffer too small
      if #t > 0 then lst:push_front(table.concat(t)) end
      return
    end

    if (size + #chunk) >= n then
      assert(n > size)
      local pos = n - size
      local data = string.sub(chunk, 1, pos)
      if pos < #chunk then
        lst:push_front(string.sub(chunk, pos + 1))
      end

      t[#t + 1] = data
      return table.concat(t)
    end

    t[#t + 1] = chunk
    size = size + #chunk
  end
end

function Buffer.self_test(EOL)
  local b = Buffer:new(EOL)
  local eol = b:eol()

  -- test next_xxx
  assert("aaa" == b:next_line("aaa" .. eol .. "bbb"))

  assert("bbbccc" == b:next_line("ccc" .. eol .. "ddd" .. eol))

  assert("ddd" == b:next_line(eol))

  assert("" == b:next_line(""))

  assert(nil == b:next_line(""))

  assert(nil == b:next_line("aaa"))

  assert("aaa" == b:next_n("123456", 3))

  assert(nil == b:next_n("", 8))

  assert("123"== b:next_n("", 3))

  assert("456" == b:next_n(nil, 3))

  b:reset()

  assert(nil == b:next_line("aaa|bbb"))

  assert("aaa" == b:next_line(nil, "|"))

  b:reset()
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local DeferQueue = class() do

local va, uv

function DeferQueue:__init()

  va = va or require "vararg"
  uv = uv or require "lluv"

  self._queue = Queue.new()
  self._timer = uv.timer():start(0, 1, function()
    self:_on_time()
    if o._queue:empty() then self._timer:stop() else self._timer:again() end
  end):stop()
  return self
end

function DeferQueue:_on_time()
  -- callback could register new function
  -- so we proceed only currently active
  -- and leave new one to next iteration
  for i = 1, self._queue:size() do
    local args = self._queue:pop()
    if not args then break end
    args(1, 1)(args(2))
  end
end

function DeferQueue:call(...)
  self._queue.push(va(...))
  if self._queue.size() == 1 then self._timer:again() end
end

function DeferQueue:close(call)
  if not self._queue then return end

  if call then self._on_time() end
  self._timer:close()
  self._queue, self._timer = nil
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local MakeErrors = function(errors)
  assert(type(errors) == "table")

  local numbers  = {} -- errno => name
  local names    = {} -- name  => errno
  local messages = {}

  for no, info in pairs(errors) do
    assert(type(info) == "table")
    local name, msg = next(info)

    assert(type(no)   == "number")
    assert(type(name) == "string")
    assert(type(msg)  == "string")
    
    assert(not numbers[no], no)
    assert(not names[name], name)
    
    numbers[no]    = name
    names[name]    = no
    messages[no]   = msg
    messages[name] = msg
  end

  local Error = class() do

  function Error:__init(no, ext)
    assert(numbers[no] or names[no], "unknown error: " ..  tostring(no))

    self._no = names[no] or no
    self._ext = ext

    return self
  end

  function Error:name()
    return numbers[self._no]
  end

  function Error:no()
    return self._no
  end

  function Error:msg()
    return messages[self._no]
  end

  function Error:ext()
    return self._ext
  end

  function Error:__tostring()
    local ext = self:ext()
    if ext then
      return string.format("[%s] %s (%d) - %s", self:name(), self:msg(), self:no(), ext)
    end
    return string.format("[%s] %s (%d)", self:name(), self:msg(), self:no())
  end

  end

  local o = setmetatable({
    __class = Error
  }, {__call = function(self, ...)
    return Error:new(...)
  end})

  for name, no in pairs(names) do
    o[name] = no
  end

  return o
end
-------------------------------------------------------------------

local function self_test()
  Buffer.self_test()
  List.self_test()
  slit_first_self_test()
  class_self_test()
end

return {
  Buffer      = Buffer;
  Queue       = Queue;
  List        = List;
  Errors      = MakeErrors;
  DeferQueue  = DeferQueue;
  class       = class;
  split_first = split_first;
  split       = split;
  usplit      = usplit;
  self_test   = self_test;
}
