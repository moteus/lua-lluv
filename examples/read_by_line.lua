-- read input stream line by line

local uv = require "lluv"
local ut = require "utils"

local host, port = "127.0.0.1", 5555

local buffer = ut.Buffer("\r\n")

local function read_data(cli, err, data)
  if err then return cli:close() end

  local line = buffer.next_line(data)
  while line do
    print(line)
    line = buffer.next_line()
  end
end

uv.tcp():connect(host, port, function(cli, err)
  if err then return cli:close() end

  cli:start_read(read_data)
end)

uv.run(debug.traceback)
