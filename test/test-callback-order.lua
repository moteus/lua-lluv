local uv = require "lluv"

local idle_cb_called  = 0;
local timer_cb_called = 0;

local  idle_handle;
local  timer_handle;

-- idle_cb should run before timer_cb 
function idle_cb(handle)
  assert(idle_handle == handle)
  assert(idle_cb_called  == 0)
  assert(timer_cb_called == 0)
  handle:stop()
  idle_cb_called = idle_cb_called + 1
end

function timer_cb(handle)
  assert(timer_handle == handle)
  assert(idle_cb_called  == 1)
  assert(timer_cb_called == 0)
  handle:stop()
  timer_cb_called = timer_cb_called + 1
end

function next_tick(handle)
  handle:stop()
  idle_handle  = uv.idle():start(idle_cb)
  timer_handle = uv.timer():start(timer_cb)
end

uv.idle():start(next_tick)

assert(idle_cb_called  == 0)
assert(timer_cb_called == 0)

uv.run()

assert(idle_cb_called  == 1)
assert(timer_cb_called == 1)
