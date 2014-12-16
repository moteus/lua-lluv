local uv     = require "lluv"
local socket = require "lluv.luasocket"
local host   = host or "127.0.0.1";
local port   = port or "8384";

local function spawn(fn, ...) coroutine.wrap(fn)(...) end

local function fiber(...) uv.defer(spawn, ...) end

fiber(function()
  local server = assert(socket.bind(host, port));

  while true do
    print("server: waiting for client connection...")
    local control = assert(server:accept())
    socket.sleep(0.5)
    control:close()
  end
end)

uv.run()
