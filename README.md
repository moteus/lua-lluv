lua-lluv
========
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv)

##Lua low level binding to [libuv](https://github.com/joyent/libuv)

## Compatible with libuv>=1.0.0

##Install

Current master
```
luarocks install lluv --server=https://rocks.moonscript.org/dev
```

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

uv.tcp()
  :bind("127.0.0.1", 5555)
  :listen(on_connection)

uv.pipe()
  :bind([[\\.\pipe\sock.echo]])
  :listen(on_connection)

uv.run()
```
