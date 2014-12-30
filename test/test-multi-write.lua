local uv   = require "lluv.unsafe"

local PASS = false

local TIMER = uv.timer():start(10000, function()
  uv.stop()
end)

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
  server:listen(on_connection)
end

uv.tcp():bind("127.0.0.1", 5555, on_bind)

uv.tcp():connect("127.0.0.1", 5555, function(cli, err)
  if err then
    io.stderr:write("Can not connect to server:", tostring(err), "\n")
    return cli:close()
  end

  cli:write{"HELLO", ", ", "WORLD", "!!!"}
  cli:close()
end)

uv.run()

if not PASS then os.exit(1) end

print("Done!")
