
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
  return str, ""
end

local function ocall(fn, ...) if fn then return fn(...) end end

-------------------------------------------------------------------
local function Buffer(eol)
  local eol  = eol or "\n"
  local neol = #eol

  local tail = ""

  local function next_line(data)
    data = data and (tail .. data) or tail

    local e, e2 = string.find(data, eol, nil, true)
    if e then
      local line = string.sub(data, 1, e - 1)
      tail = string.sub(data, e2 + 1)
      return line
    else
      tail = data
    end
    return nil
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

    tail = ""
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
local function Queue()
  local t = {}
  local self

  local function reset() t = {} return self end

  local function push(v) t[#t + 1] = v return self end

  local function pop()
    if #t == 0 then return nil end
    return table.remove(t, 1)
  end

  local function peek() return t[1] end

  local function size() return #t end

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

return {
  Buffer      = Buffer;
  Queue       = Queue;
  ocall       = ocall;
  split       = split;
  usplit      = usplit;
  split_first = split_first;
}
