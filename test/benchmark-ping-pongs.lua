local uv = require "lluv"

local function printf(...) io.write(string.format(...)) end

-- Run the benchmark for this many ms
local TIME = 15000

local TEST_PORT = 5555

local PING = "PING\n";

local start_time

local function pinger_new()

local pinger

local function pinger_close_cb(handle)
  printf("ping_pongs: %d roundtrips/s\n", (1000 * pinger.pongs) / TIME)
  pinger.complite = true
end

local function pinger_write_cb(handle, err)
  assert(not err, tostring(err))
end

local function pinger_write_ping(pinger)
  assert(pinger.tcp:write(PING, pinger_write_cb))
end

local function pinger_shutdown_cb(handle, err)
  assert(not err, tostring(err))
  assert(not pinger.complite)
  pinger.shutdown = true
end

local function pinger_read_cb(tcp, err, buf)
  if err then
    assert(err:name() == "EOF")

    -- assert(pinger_shutdown_cb_called == 1)
    tcp:close(pinger_close_cb)

    return
  end

  local len    = pinger.tail + #buf
  local count  = math.ceil(len / #PING)

  pinger.pongs = pinger.pongs + count
  pinger.tail  = len % #PING

  if (uv.now() - start_time) > TIME then
    tcp:shutdown(pinger_shutdown_cb)
  else
    for i = 1, count do
      pinger_write_ping(pinger)
    end
  end
end

local function pinger_connect_cb(handle, err)
  assert(not err, tostring(err))

  pinger_write_ping(pinger);

  assert(handle:start_read(pinger_read_cb))
end

pinger = {
  tcp   = assert(uv.tcp());
  pongs = 0;
  tail  = 0;
}

assert(pinger.tcp
  :bind("0.0.0.0", 0)
  :connect("127.0.0.1", TEST_PORT, pinger_connect_cb)
)

return pinger

end

local function start()
  start_time = uv.now()

  local p1 = pinger_new()
  local p2 = pinger_new()

  uv.run(debug.traceback)

  assert(p1.complite)
  assert(p2.complite)
end

start()
