local uv       = require "lluv"
local ut       = require "lluv.utils"
local socket   = require "lluv.ssl.luasocket"
local ssl      = require "lluv.ssl"
local sendmail = require "sendmail"

ut.corun(sendmail, {
  server = {
    address  = "localhost";
    user     = "moteus@test.localhost.com";
    password = "123456";
    ssl      = ssl.context{verify = {"none"}};
    create   = socket.ssl;
  },

  from = {
    title    = "Test";
    address  = "buh@intelcom-tg.ru";
  },

  to = {
    address = "melnichuk@incomtel.ru";
  },

  message = {"CoSocket message"}
})

uv.run()
