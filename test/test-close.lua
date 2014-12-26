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

local f = false
timer = uv.timer():start(function() f = true end)

uv.run()

assert(f == true)

print("Done!")
