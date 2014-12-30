local uv   = require "lluv"

local reg, han = uv.__registry()

local function gc(n) for i = 1, (n or 10) do collectgarbage("collect") end end

local function weak_ptr(v) return setmetatable({value = v}, {__mode = "v"}) end

function test_1()

local ptr = weak_ptr(uv.timer())

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

function test_2()

local ptr = weak_ptr(uv.timer():lock())

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

function test_3()

local ptr = weak_ptr(uv.timer():start(0, function() end))

assert(#uv.handles() == 1)

gc()

assert(nil ~= ptr.value)

assert(#uv.handles() == 1)

assert(ptr.value:locked())

uv.run()

assert(#uv.handles() == 1)

assert(not uv.handles()[1]:locked())

uv.handles()[1]:close()

assert(uv.handles()[1]:locked())

uv.run()

assert(#uv.handles() == 0)

gc()

assert(nil == ptr.value)

end

function test_4()

local counter = 4

local ptr = weak_ptr(uv.timer():start(0, 500, function(timer)
  assert(timer:locked())

  if counter == 0 then return uv.stop() end

  counter = counter - 1
  gc()
end))

assert(#uv.handles() == 1)

gc()

assert(nil ~= ptr.value)

assert(#uv.handles() == 1)

assert(ptr.value:locked())

uv.run()

assert(#uv.handles() == 1)

assert(nil ~= ptr.value)

assert(ptr.value:locked())

uv.handles()[1]:close()

assert(uv.handles()[1]:locked())

uv.run()

assert(#uv.handles() == 0)

gc()

assert(nil == ptr.value)

end

test_1()

test_2()

test_3()

test_4()

print("Done!")