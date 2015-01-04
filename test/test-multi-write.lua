local uv   = require "lluv.unsafe"

local PASS = false

local TIMER = uv.timer():start(10000, function()
  uv.stop()
end)

local function Client(host, port)
  uv.tcp():connect(host, port, function(cli, err)
    if err then
      io.stderr:write("Can not connect to server:", tostring(err), "\n")
      return cli:close()
    end

    cli:write{"HELLO", ", ", "WORLD", "!!!"}
    cli:close()
  end)
end

local function on_read(cli, err, data)
  if err then
   if err:name() == 'EOF' then
      io.stderr:write("Read done.\n")
    else
      io.stderr:write("Can not read data:", tostring(err), "\n")
    end
    return cli:close()
  end
  assert(data == "HELLO, WORLD!!!")
  PASS = true
  TIMER:close()
end

local function on_connection(server, err)
  if err then
    io.stderr:write("Can not listen on server:", tostring(err), "\n")
    return server:close()
  end

  server
    :accept()
    :start_read(on_read)
  server:close()
end

local function on_bind(server, err)
  if err then
    io.stderr:write("Can not bind on server:", tostring(err), "\n")
    return server:close()
  end

  local host, port = server:getsockname()

  io.stderr:write("Bind on:", host, ":", port, "\n")

  server:listen(on_connection)

  Client(host, port)
end

uv.tcp():bind("127.0.0.1", 0, on_bind)

uv.run()

if not PASS then os.exit(1) end

print("Done!")
