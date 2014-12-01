local socket    = require "cosocket"
local uv        = require "lluv"
local sendmail_ = require "sendmail"

local function sendmail(server, ...)
  local s = server
  if not ... then
    if type(server.server) == 'string' then
      server.server = {address = server.server}
    end
    s = server.server
  end
  assert(type(s) == "table")
  s.create = socket.tcp;

  return sendmail_(server, ...)
end

coroutine.wrap(sendmail){
  server = {
    address  = "localhost";
    user     = "moteus@test.localhost.com";
    password = "123456";
    ssl      = "sslv3";
  },

  from = {
    title    = "Test";
    address  = "moteus@test.localhost.com";
  },

  to = {
    address = {"alexey@test.localhost.com"}
  },

  message = {"CoSocket message"}
}

uv.run()
