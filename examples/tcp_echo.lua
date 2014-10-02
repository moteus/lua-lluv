local uv = require "lluv"
local server = uv.tcp()

print("BIND:", server:bind("127.0.0.1", 5555))

local function on_write(cli, err)
  if err then
    print("WRITE: ", err)
    return cli:close()
  end
end

local function on_read(cli, err, data)
  if err then
    print("READ: ", err)
    return cli:close()
  end
  cli:write(data, on_write)
  -- io.write(data)
end

print("LISTEN_START:", server:listen(function(server, err)
  print("LISTEN: ", err or "OK")
  if err then return end

  -- create client socket in same loop as server
  local cli, err = server:accept(uv.tcp(server:loop()))
  if err then print("ACCEPT: ", err) else print("ACCEPT: ", cli:getpeername()) end

  cli:start_read(on_read)
end))

uv.run()
