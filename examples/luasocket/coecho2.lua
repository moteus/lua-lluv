local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"

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

    ut.corun(function()
      -- attach socket to current coroutine
      fn(cli:attach())
    end)
  end
end

ut.corun(server, "127.0.0.1", 5555, echo_worker)

uv.run()
