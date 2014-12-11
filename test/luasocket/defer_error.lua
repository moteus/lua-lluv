local uv = require "lluv"

local host = host or "127.0.0.1"
local port = port or "8384"


local function write(s, data, cb)
  local ok, err = s:write(data, cb)
  if not ok then
    print("write return error :", err)
    os.exit(-1)
  end
  return true
end

local function on_write(cli, err,...)
  if err then
    print("Done!")
    os.exit(0)
  end
  write(cli, "hello", on_write)
end

uv.tcp():connect(host, port, function(cli, err)
  if err then
    cli:close()
    assert(false, tostring(err))
  end
  write(cli, "hello", on_write)
end)

uv.run()


