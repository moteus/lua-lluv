local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"

----------------------------------------------------------------------------
local function CreateServer(ip, port, cb)

  local function on_connect(srv, err)
    if err then return cb(nil, err) end
    local cli, err = srv:accept()
    if not cli then cb(nil, err) end
    return cb(cli)
  end

  local function on_bind(srv, err)
    if err then
      srv:close()
      return error("Can not bind to " .. ip .. ":" .. port .. " : " .. tostring(err))
    end

    srv:listen(on_connect)
  end

  uv.tcp():bind(ip, port, on_bind)
end
----------------------------------------------------------------------------

local function echo_worker(sock, err)
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
  ut.corun(echo_worker, ...)
end)

uv.run()
