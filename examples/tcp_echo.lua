-- Not finished
-- currently only print data to stout

local uv = require "lluv"
local server = uv.tcp()

print("BIND:", server:bind("127.0.0.1", 5555))

print("LISTEN_START:", server:listen(5, function(server, err)
  print("LISTEN: ", err or "OK")
  if err then return end
  local cli, err = server:accept(uv.tcp(server:loop()))
  print("ACCEPT: ", cli or err)
  cli:start_read(function(cli, err, data)
    if err then
      print("READ: ", err)
      return cli:close()
    end
    io.write(data)
  end)
end))

uv.run()
