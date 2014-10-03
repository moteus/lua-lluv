local uv = require "lluv"

local function printf(...) io.write(string.format(...)) end

local NUM_TICKS  = 2 * 1000 * 1000

local ticks
local idle_handle
local timer_handle


local function idle_cb(handle)
  ticks = ticks + 1
  if ticks == NUM_TICKS then handle:stop() end
end

local function idle2_cb(handle)
  ticks = ticks + 1
end

local function timer_cb(handle)
  idle_handle:stop()
  handle:stop()
end

local function loop_count()

  ticks = 0
  idle_handle = uv.idle():start(idle_cb)

  local ns = uv.hrtime()
  uv.run();
  ns = uv.hrtime() - ns

  assert(ticks == NUM_TICKS);

  printf("loop_count: %d ticks in %.2fs (%.0f/s)\n",
       NUM_TICKS,
       ns / 1e9,
       NUM_TICKS / (ns / 1e9));

end

local function loop_count_timed()

  ticks = 0
  idle_handle = uv.idle():start(idle2_cb)

  timer_handle = uv.timer():start(5000, timer_cb);

  uv.run();

  printf("loop_count: %u ticks (%.0f ticks/s)\n", ticks, ticks / 5.0);

end


loop_count()

loop_count_timed()