local file = assert(arg[1] or "testclnt.lua")
local fn = assert(loadfile(file))
local co = coroutine.wrap(fn)

co()

require "lluv".run(debug.traceback)
