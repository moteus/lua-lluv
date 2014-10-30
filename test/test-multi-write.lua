local uv   = require "lluv.unsafe"

local PASS = false

local TIMER = uv.timer():start(10000, function()
  uv.walk(function(h) h:close() end)
  uv.stop()
end)

local function on_read(cli, err, data)
  if err then return cli:close() end
  assert(data == "HELLO, WORLD!!!")
  PASS = true
  TIMER:close()
end

local function on_connection(server, err)
  if err then return server:close() end
  server
    :accept()
    :start_read(on_read)
  server:close()
end

uv.tcp()
  :bind("127.0.0.1", 5555)
  :listen(on_connection)

uv.tcp()
  :connect("127.0.0.1", 5555, function(cli)
    cli:write{"HELLO", ", ", "WORLD", "!!!"}
    cli:close()
  end)


uv.run()

if not PASS then os.exit(1) end

print("Done!")
