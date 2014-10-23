
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

-------------------------------------------------------------------
local function Buffer(eol)
  local EOL = eol or "\n"

  local tail = ""

  local function next_line(data, eol)
    data = data and (tail .. data) or tail

    local s1, s2 = split_first(data, eol or EOL, true)
    if s2 then
      tail = s2
      return s1
    end
    tail = data
  end

  local function next_n(data, n)
    data = data and (tail .. data) or tail
    if n > #data then
      tail = data
      return nil
    end

    local res = string.sub(data, 1, n)
    tail = string.sub(data, n+1)
    return res
  end

  local function reset()
    tail = ""
  end

  local function self_test()
    local eol = EOL

      -- test next_xxx
    assert("aaa" == next_line("aaa" .. eol .. "bbb"))
    assert("bbb" == tail, tail)

    assert("bbbccc" == next_line("ccc" .. eol .. "ddd" .. eol))
    assert("ddd"..eol == tail, tail)

    assert("ddd" == next_line(eol))
    assert(eol == tail, "'" .. tail .."'")

    assert("" == next_line(""))
    assert("" == tail, "'" .. tail .."'")

    assert(nil == next_line(""))
    assert("" == tail, "'" .. tail .."'")

    assert(nil == next_line("aaa"))
    assert("aaa" == tail, "'" .. tail .."'")

    assert("aaa" == next_n("123456", 3))
    assert("123456" == tail, "'" .. tail .."'")

    assert(nil == next_n("", 8))
    assert("123456" == tail, "'" .. tail .."'")

    assert("123"== next_n("", 3))
    assert("456" == tail, "'" .. tail .."'")

    assert("456" == next_n(nil, 3))
    assert("" == tail, "'" .. tail .."'")

    reset()

    assert(nil == next_line("aaa|bbb"))
    assert("aaa|bbb" == tail, tail)

    assert("aaa" == next_line(nil, "|"))
    assert("bbb" == tail, tail)

    reset()
  end

  local function append(data)
    tail = tail .. data
  end

  return {
    next_line = next_line;
    next_n    = next_n;
    reset     = reset;
    append    = append;
    self_test = self_test;
  }
end
-------------------------------------------------------------------

-------------------------------------------------------------------
local function List()

  local t, self

  local function reset()
    t = {first = 0, last = -1}
    return self
  end

  local function push_front(v)
    assert(v ~= nil)
    local first = t.first - 1
    t.first, t[first] = first, v
    return self
  end

  local function push_back(v)
    assert(v ~= nil)
    local last = t.last + 1
    t.last, t[last] = last, v
    return self
  end

  local function peek_front()
    return t[t.first]
  end

  local function peek_back()
    return t[t.last]
  end

  local function pop_front()
    local first = t.first
    if first > t.last then return end

    local value = t[first]
    t.first, t[first] = first + 1

    return value
  end

  local function pop_back()
    local last = t.last
    if t.first > last then return end

    local value = t[last]
    t.last, t[last] = last - 1

    return value
  end

  local function size()
    return t.last - t.first + 1
  end

  local function empty()
    return t.first > t.last
  end

  local function self_test()
    local q = reset()

    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(q.push_back(1) == q)
    assert(q.empty() == false)
    assert(q.size()  == 1)

    assert(q.peek_back() == 1)
    assert(q.empty() == false)
    assert(q.size()  == 1)

    assert(q.peek_front() == 1)
    assert(q.empty() == false)
    assert(q.size()  == 1)

    assert(q.pop_back() == 1)
    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(q.push_front(1) == q)
    assert(q.empty() == false)
    assert(q.size()  == 1)

    assert(q.pop_front() == 1)
    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(q.pop_back() == nil)
    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(q.pop_front() == nil)
    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(false == pcall(q.push_back))
    assert(q.empty() == true)
    assert(q.size()  == 0)

    assert(false == pcall(q.push_front))
    assert(q.empty() == true)
    assert(q.size()  == 0)
    
    q.push_back(1).push_back(2)
    assert(q.pop_back() == 2)
    assert(q.pop_back() == 1)

    q.push_back(1).push_back(2)
    assert(q.pop_front() == 1)
    assert(q.pop_front() == 2)

  end

  self = {
    push_front = push_front,
    push_back  = push_back,
    peek_front = peek_front,
    peek_back  = peek_back,
    pop_front  = pop_front,
    pop_back   = pop_back,
    size       = size,
    empty      = empty,
    reset      = reset,

    self_test  = self_test,
  }

  return self.reset()
end
-------------------------------------------------------------------

-------------------------------------------------------------------
local function Queue()
  local q = List()

  local function reset()        q.reset()      return self end
  local function push(v)        q.push_back(v) return self end
  local function pop()   return q.pop_front()              end
  local function peek()  return q.peek_front()             end
  local function size()  return q.size()                   end

  self = {
    reset = reset,
    push  = push,
    pop   = pop,
    peek  = peek,
    size  = size,
  }

  return self
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

  local Error = {} do
  Error.__index = Error

  function Error:new(no, ext)
    assert(numbers[no] or names[no], "unknown error: " ..  tostring(no))

    local o = setmetatable({}, self)
    o._no = names[no] or no
    o._ext = ext

    return o
  end

  function Error:name()
    return assert(numbers[self._no], self._no)
  end

  function Error:no()
    return self._no
  end

  function Error:msg()
    return assert(messages[self._no], self._no)
  end

  function Error:ext()
    return self._ext
  end

  function Error:__tostring()
    local ext = self:ext()
    if ext then
      return string.format("[%s] %s (%d) - %s", self:name(), self:message(), self:no(), ext)
    end
    return string.format("[%s] %s (%d)", self:name(), self:msg(), self:no())
  end

  end

  local o = setmetatable({}, {__call = function(self, ...)
    return Error:new(...)
  end})
  
  for name, no in pairs(names) do
    o[name] = no
  end

  return o
end
-------------------------------------------------------------------

local function self_test()
  Buffer().self_test()
  List().self_test()
  slit_first_self_test()
end

return {
  Buffer      = Buffer;
  Queue       = Queue;
  List        = List;
  Errors      = MakeErrors;
  split_first = split_first;
  split       = split;
  usplit      = usplit;
  self_test   = self_test;
}
