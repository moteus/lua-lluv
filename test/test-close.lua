local uv = require "lluv"
print("-----------------------------------------")
print("libuv:", uv.version())
print("lluv :", uv._VERSION)
print("-----------------------------------------")

local loop = assert(uv.default_loop())
local timer = assert(uv.timer())
uv.close(true)
assert(timer:closed())

local loop2 = assert(uv.default_loop())
assert(loop2 ~= loop)

local start = false
local close = false

timer = uv.timer()
  :start(function() start = true end)
  :close(function() close = true end)

uv.close(true)

assert(timer:closed())
assert(close)
assert(not start)

local timer = uv.timer()
coroutine.wrap(function()
  uv.close(true)
end)()
assert(timer:closed())

print("Done!")
