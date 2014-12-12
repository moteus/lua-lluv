local uv = require "lluv"

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

uv.tcp()
:bind("127.0.0.1", 5555, function(server, err, host, port)
  if err then
    print("Can not bind:", tostring(err))
    return server:close()
  end

  print("Bind on: " .. host .. ":" .. port)

  print("LISTEN_START:", server:listen(function(server, err)
    print("LISTEN: ", err or "OK")
    if err then return end

    -- create client socket in same loop as server
    local cli, err = server:accept()
    if not cli then print("ACCEPT: ", err) else print("ACCEPT: ", cli:getpeername()) end

    cli:start_read(on_read)
  end))
end)

uv.run()
