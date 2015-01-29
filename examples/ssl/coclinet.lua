local uv     = require "lluv"
local ut     = require "lluv.utils"
local ssl    = require "lluv.ssl"
local socket = require "lluv.ssl.luasocket"
local config = require "./config"

local ctx = assert(ssl.context(config))

local function ping() ut.corun(function()
  local cli = socket.ssl(ctx:client())
  print("Connect  ", cli:connect("127.0.0.1", 8881))
  print("Recv:", cli:receive("*a"))
  cli:close()
  ping()
end) end

ping()

uv.run()
