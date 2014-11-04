-- read input stream line by line

local uv = require "lluv"
local ut = require "lluv.utils"

local host, port = "127.0.0.1", 5555

local buffer = ut.Buffer.new("\r\n")

local function read_data(cli, err, data)
  if err then return cli:close() end

  buffer:append(data)
  while true do
    local line = buffer:next_line()
    if not line then break end
    print(line)
  end
end

uv.tcp():connect(host, port, function(cli, err)
  if err then return cli:close() end

  cli:start_read(read_data)
end)

uv.run(debug.traceback)
