local uv      = require "lluv"
local socket  = require "socket"

-- Because in this case we use LuaSocket to make sockets 
-- its not possible test lightuserdata variant

local function make_sock_pair(host, port)
  local srv = assert(socket.bind(host, port))
  local s1 = assert(socket.connect(host, port))
  local s2 = assert(srv:accept())
  srv:close()
  return s1, s2
end

local s1, s2 = make_sock_pair('127.0.0.1', '9009')

local fd1, err = assert(s1:getfd())
assert(err == nil, tostring(err))
assert(type(fd1) == 'number')

local poll = uv.poll_socket(fd1)
local pfd, err = poll:fileno()
assert(err == nil, tostring(err))
assert(fd1 == pfd, tostring(pfd))

if math.type then
  local tfd = math.type(pfd)
  assert(tfd == 'integer', tfd)
end

print('Done!')
