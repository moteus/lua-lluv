local uv  = require"lluv"

local function ver()
  local min, maj, pat = uv.version(true)
  return min * 100000 + maj * 100 + pat
end

if ver() < 102700 then
  print('Supported since 1.27.0. Got ' .. uv.version())
  return
end

local host, port = "127.0.0.1", 5555

local server = uv.udp():bind(host,port)

server:start_recv(function(self, err, msg, flag, host, port)
  if err then
    print("Server error:", err)
    return server:close()
  end
end)

local cli = uv.udp()
uv.timer():start(1000,function()
  io.write('Connect (invalid IP) - ')
  local ok, err = cli:connect('127.0.0.1222', port)
  assert(ok == nil)
  assert(err:name() == 'EINVAL')
  io.write('ok\n')

  io.write('Connect (invalid port) - ')
  local ok, err = cli:connect('127.0.0.1', 65536)
  assert(ok == nil)
  assert(err:name() == 'EINVAL')
  io.write('ok\n')

  io.write('Connect - ')
  local ok, err = cli:connect(host, port)
  assert(cli == ok)
  local a, b = cli:getpeername()
  assert(a == host)
  assert(b == port)
  io.write('ok\n')

  io.write('Disconnect - ')
  local ok, err = cli:connect()
  assert(cli == ok)
  local a, b = cli:getpeername()
  assert(a == nil)
  assert(b:name() == 'ENOTCONN')
  io.write('ok\n')

  io.write('Connect (cb) - ')
  local ok, err = cli:connect(host, port, function(self, err, a, b)
    assert(a == host)
    assert(b == port)
    io.write('ok\n')

    io.write('Try send string - ')
    ok, err = cli:try_send('hello')
    assert(5 == ok)
    io.write('ok\n')

    io.write('Send string - ')
    ok = cli:send('hello')
    assert(self == ok)
    io.write('ok\n')

    io.write('Send string(cb) - ')
    ok = cli:send('hello', function(self, err, ctx)
      assert('Context' == ctx)
      assert(err == nil)
      io.write('ok\n')

      io.write('Try send table - ')
      ok, err = cli:try_send{'hello', 'world'}
      assert(10 == ok)
      io.write('ok\n')

      io.write('Send table - ')
      ok = cli:send{'hello', 'world'}
      assert(self == ok)  
      io.write('ok\n')

      io.write('Send table (cb) - ')
      ok = cli:send({'hello', 'world'}, function(self, err, ctx)
        assert(err == nil)
        assert('Context' == ctx)
        io.write('ok\n')
        uv.timer():start(1000, function() cli:close() server:close() end)
      end, 'Context')

      assert(self == ok)  
    end, 'Context')

    assert(self == ok)
  end)
end)

uv.run(debug.traceback)
