local socket = require "cosocket"
local uv     = require "lluv"
local ut     = require "lluv.utils"

----------------------------------------------------------------------------
local function CreateServer(ip, port, cb)

  local function on_connect(srv, err)
    if err then return cb(nil, err) end
    local cli, err = srv:accept()
    if not cli then cb(nil, err) end
    return cb(cli)
  end

  uv.tcp()
    :bind(ip, port)
    :listen(on_connect)
end
----------------------------------------------------------------------------

local echo_worker = function(sock, err)
  if not sock then return end

  local cli = socket.tcp(sock)

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

CreateServer("127.0.0.1", 5555, function(...)
  coroutine.wrap(echo_worker)(...)
end)

uv.run()
