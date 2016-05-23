lua-lluv
========
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv)

##Lua low level binding to [libuv](https://github.com/libuv/libuv)

## Compatible with libuv>=1.0.0

##Install

Current master
```
luarocks install lluv --server=https://rocks.moonscript.org/dev
```

###Related projects
 * [lluv-ssl](https://github.com/moteus/lua-lluv-ssl) - SSL/TLS sockets for lluv library
 * [lluv-websocket](https://github.com/moteus/lua-lluv-websocket) - Websocket sockets for lluv library
 * [lluv-redis](https://github.com/moteus/lua-lluv-redis) - Redis client for lluv library
 * [lluv-memcached](https://github.com/moteus/lua-lluv-memcacheds) - Memcached client for lluv library
 * [lua-lluv-ftp](https://github.com/moteus/lua-lluv-ftp) - FTP client for lluv library
 * [lluv-poll-zmq](https://github.com/moteus/lua-lluv-poll-zmq) - [ZMQ](http://zeromq.org) poller for lluv library
 * [lluv-rs232](https://github.com/moteus/lua-lluv-rs232) - Serial port communication library for lluv library
 * [lluv-gsmmodem](https://github.com/moteus/lua-lluv-gsmmodem) - Control GSM modem connected to serial port using AT commands.
 * [lua-gntp](https://github.com/moteus/lua-gntp) - lluv connector to Growl notification system
 * [lua-lluv-esl](https://github.com/moteus/lua-gntp) - FreeSWITCH ESL implementation for lluv library

### Example

Basic tcp/pipe echo server
```Lua
local uv = require "lluv"

local function on_write(cli, err)
  if err then return cli:close() end
end

local function on_read(cli, err, data)
  if err then return cli:close() end
  cli:write(data, on_write)
end

local function on_connection(server, err)
  if err then return server:close() end
  server
    :accept()
    :start_read(on_read)
end

local function on_bind(server, err, host, port)
  if err then
    print("Bind fail:" .. tostring(err))
    return server:close()
  end

  if port then host = host .. ":" .. port end
  print("Bind on: " .. host)

  server:listen(on_connection)
end

uv.tcp():bind("127.0.0.1", 5555, on_bind)

uv.pipe():bind([[\\.\pipe\sock.echo]], on_bind)

uv.run()
```

Coroutine based echo server
```Lua
local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"

local function echo(cli)
  while true do
    local msg, err = cli:receive("*r")
    if not msg then break end
    cli:send(msg)
  end
  cli:close()
end

local function server(host, port, fn)
  local srv = socket.tcp()

  srv:bind(host, port)

  while true do
    local cli = srv:accept()

    ut.corun(function()
      -- attach socket to current coroutine
      fn(cli:attach())
    end)
  end
end

ut.corun(server, "127.0.0.1", 5555, echo)

uv.run()
```
## Using `lluv.luasocket` with origin `LuaSocket` modules.

The main problem that LuaSocket uses `protect` function to wrap its 
functions (e.g. http.request) So there may be problem with yield from such functions.
The problem solved since commit [5edf093](https://github.com/diegonehab/luasocket/commit/5edf093643cceb329392aec9606ab3988579b821)
and only for Lua >= 5.2. So if you use Lua 5.1/LuaJIT or you can not
update LuaSocket you have trouble with using `lluv.luasocket` module.

To solve this problem you can use [try](https://github.com/moteus/lua-try) or [try-lua](https://github.com/hjelmeland/try-lua) modules.
This modules implement same functionality as LuaSocket's `protect` function.
To replace LuaSocket implementation with this module you can use this code.
```Lua
local socket = require "socket"
local try    = require "try"

socket.newtry  = try.new
socket.protect = try.protect
socket.try     = try.new()
```
This allows you use old version of LuaSocket with Lua >=5.2.
Also if you use [try-lua](https://github.com/hjelmeland/try-lua) and bacause of it uses `pcall` function
to implement `protect` this allows use `lluv.luasocket` on LuaJIT and on Lua 5.1 with [Coco](http://coco.luajit.org/) patch.

But this is not help solve problem with stock Lua 5.1.
I do not know full solution for this but with using `try.co` module
you can use `socket.http`, `socket.smtp` moudules.

At first you should replace socket.protect with try.co implementation
```Lua
local socket = require "socket"
local try    = require "try.co"

socket.newtry  = try.new
socket.protect = try.protect
socket.try     = try.new()
```

And when you have to use socket object from `lluv.luasocket` module you should
manually attach it to work coroutine.

```Lua
local function http_request(url)
  -- this is work coroutine
  local co = coroutine.running()
  http.request{
    ...
    create = function()
      -- attach to work coroutine
      return socket.tcp():attach(co)
    end;
  }
end
```
You can also check out full example [cohttp](examples/luasocket/cohttp.lua)
