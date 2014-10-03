local uv = require "lluv"

local function printf(...) io.write(string.format(...)) end

local NUM_TIMERS = 5 * 1000 * 1000

local timer_cb_called = 0
local close_cb_called = 0

local function timer_cb(handle)
  timer_cb_called = timer_cb_called + 1
end

local function close_cb(handle)
  close_cb_called = close_cb_called + 1
end

local function million_timers()
  local timers = {}

  local before_all
  local before_run
  local after_run
  local after_all
  local timeout = 0

  before_all = uv.hrtime()
  for i = 1, NUM_TIMERS do
    if i % 1000 == 0 then timeout = timeout + 1 end
    local t, err = uv.timer()
    assert(t, tostring(err))
    t, err = t:start(timeout, timer_cb)
    assert(t, tostring(err))
    timers[#timers + 1] = t
  end

  before_run = uv.hrtime()
  assert(0 == uv.run())
  after_run = uv.hrtime()

  for i = 1, NUM_TIMERS do
    timers[i]:close(close_cb)
  end
  
  assert(0 == uv.run())
  after_all = uv.hrtime();

  assert(timer_cb_called == NUM_TIMERS);
  assert(close_cb_called == NUM_TIMERS);

  printf("%.2f seconds total\n",    (after_all - before_all)  / 1e9)
  printf("%.2f seconds init\n",     (before_run - before_all) / 1e9)
  printf("%.2f seconds dispatch\n", (after_run - before_run)  / 1e9)
  printf("%.2f seconds cleanup\n",  (after_all - after_run)   / 1e9)

end

million_timers()
