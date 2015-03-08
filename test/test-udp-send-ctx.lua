local uv  = require"lluv"

local host, port = "127.0.0.1", 5555

local server = uv.udp():bind(host,port)

print(server:start_recv(function(self, err, msg, flag, host, port)
  if err then
    print("Server error:", err)
    return server:close()
  end
  print("Server read:", msg, host, port)
  server:send(host, port, msg)
end))

local cli = uv.udp()
uv.timer():start(1000,function()
  cli:send(host, port, "hello", function(self, err, ctx)
    assert(self == cli)
    assert(err == nil)
    assert(ctx == nil)

    cli:send(host, port, {"hello", " ", "world"}, function(self, err, ctx)
      assert(self == cli)
      assert(err == nil)
      assert(ctx == nil)
      cli:send(host, port, "hello", function(self, err, ctx)
        assert(self == cli)
        assert(err == nil)
        assert(ctx == "Context")
        cli:send(host, port, {"hello", " ", "world"}, function(self, err, ctx)
          assert(self == cli)
          assert(err == nil)
          assert(ctx == "Context")
          uv.timer():start(1000, function()
            cli:close()
            server:close()
          end)
        end, "Context")
      end, "Context")
    end)
  end)
end)

uv.run(debug.traceback)
