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

  local function on_bind(server, err, host, port)
    if err then
      io.stderr:write("Can not bind on server:", tostring(err), "\n")
      return server:close()
    end
    server:listen(on_connection)
  end

  local server = uv.tcp()
  local ok, err = server:bind(host, port)

  if ok then
    local h, p = server:getsockname()
    if not h then
      io.stderr:write("Can not get current socket port:" .. tostring(p) .. "\n")
      server:close()
      return nil, p
    end
    host, port = h, p
  end

  io.stderr:write("Bind on " .. tostring(host) .. ":" .. tostring(port) .. " - " .. (err and tostring(err) or "pass") .. "\n")

  uv.defer(on_bind, server, err, host, port)

  if not ok then return nil, err end

  return port
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

  local port = Server(0, "127.0.0.1", function(cli)
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

  uv.timer():start(5000, function()
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

    cli:connect("127.0.0.1", port, function(cli, err)
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
  end)

  uv.run()

  uv.close(true)

  assert(PASS)
end

test_1()

test_2()

print("Done!")