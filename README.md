lua-lluv
========

Lua binding to libuv

## Compatiable with libuv>=1.0.0

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

local function on_connection(ctor) return function(server, err)
  if err then return server:close() end
  server
    :accept(ctor(server:loop()))
    :start_read(on_read)
end end

uv.tcp()
  :bind("127.0.0.1", 5555)
  :listen(on_connection(uv.tcp))

uv.pipe()
  :bind([[\\.\pipe\sock.echo]])
  :listen(on_connection(uv.pipe))

uv.run()
```
