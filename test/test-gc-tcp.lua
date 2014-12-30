local uv   = require "lluv"

local reg, han = uv.__registry()

local function gc(n) for i = 1, (n or 10) do collectgarbage("collect") end end

local function weak_ptr(v) return setmetatable({value = v}, {__mode = "v"}) end

local function Server(port, host, cb)
  if type(host) ~= 'string' then
    host, cb = "*", host
  end

  local function on_connection(server, err)
    if err then
      io.stderr:write("Can not listen on server:", tostring(err), "\n")
      return server:close()
    end
    local cli, err = server:accept()
    if not cli then
      io.stderr:write("Can not accept new connection:", tostring(err), "\n")
    else
      cb(cli)
    end
  end

  local function on_bind(server, err)
    if err then
      io.stderr:write("Can not bind on server:", tostring(err), "\n")
      return server:close()
    end
    server:listen(on_connection)
  end

  uv.tcp():bind(host, port, on_bind)
end

function test_1()

local ptr = weak_ptr(uv.tcp())

assert(#uv.handles() == 1)

gc()

assert(#uv.handles() == 1)

assert(nil == ptr.value)

do local h = uv.handles()[1]

assert(h:locked())

assert(h:closing())

end

uv.run()

assert(#uv.handles() == 0)

end

function test_2()
  local PASS = false

  Server(5555, function(cli)
    uv.timer():start(2000, function(self)
      self:close()
      cli:close()
    end)

    cli:start_read(function(cli, err, data)
      if err then return cli:close() end
      cli:write(data)
    end)
  end)

  uv.timer():start(10000, function() uv.stop() end)

  local function on_data(cli, err, data)
    if err then
      assert(err:name() == 'EOF')
      assert(not cli:locked())
      PASS = true
      return uv.stop()
    end

    assert(cli:locked())
  end

  local cli = uv.tcp()
  assert(not cli:locked())

  cli:connect("127.0.0.1", 5555, function(cli, err)
    assert(not err, tostring(err))
    assert(not cli:locked())
    cli:write("hello", function()
      assert(not cli:locked())
      cli:start_read(on_data)
      assert(cli:locked())
    end)
    assert(cli:locked())
  end)

  assert(cli:locked())

  uv.run()

  uv.close(true)

  assert(PASS)
end

test_1()

test_2()

print("Done!")