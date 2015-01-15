if _VERSION == "Lua 5.1" then
  -- Lua 5.1 does not support yield accross
  -- C function so we use `try.co` module to
  -- replace default implementation of LuaSocket
  -- protect functionality.

  local socket = require "socket"
  local try    = require "try.co"

  socket.newtry  = try.new
  socket.protect = try.protect
  socket.try     = try.new()
end

local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"
local http   = require "socket.http"

local function http_request(url)
  local co = coroutine.running()
  print("HTTP Request: ", http.request{
    url    = url;
    create = function()
      -- for Lua >= 5.2 you can just use `socket.tcp`
      return socket.tcp():attach(co)
    end;
  })
end

ut.corun(http_request, "http://google.ru")
ut.corun(http_request, "http://google.ru")

uv.run()
