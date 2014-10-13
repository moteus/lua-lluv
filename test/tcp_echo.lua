local uv = require "lluv.unsafe"

print("Echo server:", uv.tcp():bind("127.0.0.1", 5555):listen(function(server, err)
  if err then return server:close() end

  server:accept():start_read(function(cli, err, data)
    if err then return cli:close() end
    cli:write(data)
  end)

end))

uv.run()
