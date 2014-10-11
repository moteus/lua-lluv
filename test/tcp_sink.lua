local uv = require "lluv.unsafe"

uv.tcp():bind("127.0.0.1", 5555):listen(function(server, err)
  server:accept():start_read(function(cli, err)
    if err then return cli:close() end
  end)
end)

uv.run()
