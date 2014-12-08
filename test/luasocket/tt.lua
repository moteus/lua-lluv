local uv = require "lluv"

local host = host or "127.0.0.1"
local port = port or "8384"

local function write(s, data, cb)
  local ok, err = s:write(data, cb)
  if not ok then cb(s, err) end
  return true
end

local i, j = 1, 1

local function on_write(cli, err,...)
  if err then
    print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    print(cli, err, ...)
    print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    if j == 2 then return end
    j = j + 1
  end
  print("Write #" .. i .. " done.")
  i = i + 1
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


