local uv = require "lluv"

local function gc(n) for i = 1, (n or 10) do collectgarbage("collect") end end

local function weak_ptr(v) return setmetatable({value = v}, {__mode = "v"}) end

local function test_1()
  local timer = uv.timer()

  assert(timer.data == nil)

  timer.data = 123
  assert(timer.data == 123)

  local t = {}
  timer.data = t
  assert(timer.data == t)

  uv.close(true)
end

local function test_2()
  local t = {}
  uv.timer().data = t
  gc()
  assert(uv.handles()[1]:closing())

  uv.close(true)
end

local function test_3()
  local timer = uv.timer()
  timer.data = 123
  local flag = false

  timer:close(function(self)
    assert(self:closed())
    assert(self.data == 123)
    flag = true
  end)

  uv.close(true)

  assert(flag)
end

local function test_4()
  local timer = uv.timer()

  local ptr
  do local t = {}
  ptr = weak_ptr(t)
  timer.data = t
  assert(timer.data)
  end

  gc()

  assert(timer.data)
  assert(ptr.value)

  timer.data = nil

  gc()

  assert(ptr.value == nil)

  uv.close(true)
end

test_1()

test_2()

test_3()

test_4()

print("Done!")
