local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"

local function spawn(fn, ...)
  coroutine.wrap(fn)(...)
end

local function fiber(...)
  -- we must run `spawn` from main thread
  uv.defer(spawn, ...)
end

local function echo_worker(cli)
  cli:settimeout(5)

  while true do
    local msg, err = cli:receive("*r")

    if msg then
      io.write(msg)
      cli:send(msg)
    else
      print("\n<ERROR> - ", err)
      if err ~= "timeout" then break end
    end

  end

  cli:close()
end

local function server(host, port, fn)
  local srv = socket.tcp()

  assert(srv:bind(host, port))

  while true do
    local cli, err = srv:accept()

    if not cli then
      print("Accept error: ", err)
      break
    end

    fiber(function()
      cli:reset_co() -- change coroutine-owner for socket
      fn(cli)
    end)

  end
end

fiber(server, "127.0.0.1", 5555, echo_worker)

uv.timer():start(10000, 10000, function()
  print("#IDLE TIMER")
end)

uv.run()
