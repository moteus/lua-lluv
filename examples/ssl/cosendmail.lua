local uv        = require "lluv"
local ut        = require "lluv.utils"
local ssl       = require "lluv.ssl"
local socket    = require "lluv.ssl.luasocket"
local sendmail  = require "sendmail"

local Context = ssl.context{
  -- ...
}

local ssl_create = function() return socket.ssl(Context) end

ut.corun(function() print(sendmail{
  server = {
    address  = "localhost"; port = 465;
    user     = "moteus@test.localhost.com";
    password = "123456";
    create   = ssl_create;
  },

  from = {
    title    = "Test";
    address  = "moteus@test.localhost.com";
  },

  to = {
    address = {"alexey@test.localhost.com"}
  },

  message = {"CoSocket message"}
}) end)

uv.run()
