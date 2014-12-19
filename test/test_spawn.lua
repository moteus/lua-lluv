local uv = require "lluv"

local lua  = uv.exepath()
local fake = lua .. "123456"

local counter = 0

local proc1
proc1 = uv.spawn({
  file = lua;
  args = {};
}, function(handle, err, status, signal)
  counter = counter + 1
  assert(handle == proc1)
  assert(err == nil)
  assert(status == 0)
end)

assert(proc1)
assert(proc1:active())
assert(not proc1:closing())

local proc2
proc2 = uv.spawn({
  file = fake;
  args = {};
}, function(handle, err, status, signal)
  counter = counter + 1
  assert(handle == proc2)
  assert(err ~= nil)
  assert(status == nil)
end)

assert(proc2)
assert(not proc2:active())
assert(not proc2:closing())

local proc3
proc3 = uv.spawn({
  file = lua;
  args = {};
})

assert(proc3)
assert(proc3:active())
assert(not proc3:closing())

local proc4, err
proc4, err = uv.spawn({
  file = fake;
  args = {};
})

assert(proc4 == nil)
assert(err ~= nil)

assert(#uv.handles() == 3)

uv.run()

assert(counter == 2)

print("Done!")
