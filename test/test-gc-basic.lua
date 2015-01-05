local uv = require "lluv"

local function gc(n) for i = 1, (n or 10) do collectgarbage("collect") end end

local function weak_ptr(v) return setmetatable({value = v}, {__mode = "v"}) end

local HANDLES = {
  check    = uv.check;
  prepare  = uv.prepare;
  idle     = uv.prepare;
  fs_event = uv.fs_event;
  fs_poll  = uv.fs_poll;
  signal   = uv.signal;
}

local START = {
  idle    = function(h, cb) h:start(function(self, err) cb(self, err) end) end;
}

local function TEST(name, ctor)

io.write("Testing: ", name, " ")

local function test_1()

  local ptr = weak_ptr(ctor())

  assert(#uv.handles() == 1)

  gc()

  assert(#uv.handles() == 1)

  assert(nil == ptr.value)

  do local h = uv.handles()[1]

  assert(h:locked())

  assert(h:closing())

  end

  uv.run()

  assert(#uv.handles() == 0)

end

local function test_2()

  local ptr = weak_ptr(ctor():lock())

  assert(#uv.handles() == 1)

  gc()

  assert(nil ~= ptr.value)

  assert(#uv.handles() == 1)

  do local h = uv.handles()[1]

  assert(h:locked())

  assert(not h:closing())

  end

  uv.run()

  assert(#uv.handles() == 1)

  uv.handles()[1]:close()

  uv.run()

  assert(#uv.handles() == 0)

  gc()

  assert(nil == ptr.value)

end

local function test_3()

  if not START[name] then return end

  local ptr, flag
  do
    local h = ctor()
    ptr = weak_ptr(h)
    assert(not h:locked())

    START[name](h, function(self, err)
      assert(self:locked())
      self:stop()
      assert(not self:locked())
      flag = true
    end)

    assert(h:locked())
  end

  gc()

  assert(nil ~= ptr.value)

  assert(#uv.handles() == 1)

  uv.run()

  assert(flag)

  gc()

  assert(nil == ptr.value)

  assert(uv.handles()[1])

  assert(uv.handles()[1]:locked())

  assert(uv.handles()[1]:closing())

  uv.run()

  assert(#uv.handles() == 0)
end

test_1()

test_2()

test_3()

io.write("done!\n")

end

for k, v in pairs(HANDLES) do
  TEST(k, v)
end
