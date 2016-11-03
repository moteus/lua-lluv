local uv      = require "lluv"
local socket  = require "socket"

local function make_sock_pair(host, port)
  local srv = assert(socket.bind(host, port))
  local s1 = assert(socket.connect(host, port))
  local s2 = assert(srv:accept())
  srv:close()
  return s1, s2
end

local s1, s2 = make_sock_pair('127.0.0.1', '9009')

-- clone socket handle
local h1 = uv.os_handle(s1:getfd(), true)

-- close socket object
s1:close()

local child = uv.spawn({
  file = "lua";
  args = {"echo-stdout-tcp.lua"},
  stdio = {{}, h1, 1}
},function(...)
  print(...)
end)

local MESSAGE = ''

uv.poll_socket(s2:getfd()):start(function(...)
  MESSAGE = MESSAGE .. assert(s2:receive("*l"))
end):unref()

uv.timer():start(10000, function()
  print("Timeout")
  if child then child:kill() end
  uv.stop()
end):unref()

uv.run()

assert(MESSAGE == 'HELLO WORLD')