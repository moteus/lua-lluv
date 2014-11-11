local socket = require "cosocket"
local uv     = require "lluv"
local http   = require "socket.http"

local function http_request(url)
  print("HTTP Request: ", http.request{
    url    = url;
    create = socket.tcp;
  })
end

coroutine.wrap(http_request)("http://google.ru")
coroutine.wrap(http_request)("http://google.ru")

-- LuaSocket version
print("HTTP Request: ", http.request{url = "http://google.ru"})

uv.run()
