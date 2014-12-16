local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"
local http   = require "socket.http"

local function http_request(url)
  print("HTTP Request: ", http.request{
    url    = url;
    create = socket.tcp;
  })
end

ut.corun(http_request, "http://google.ru")
ut.corun(http_request, "http://google.ru")

-- LuaSocket version
print("HTTP Request: ", http.request{url = "http://google.ru"})

uv.run()
