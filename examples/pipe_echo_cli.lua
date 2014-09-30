local uv = require "lluv"

local counter = 0

local function on_write(cli, err)
  if err then
    cli:close()
    if err:name() ~= "EOF" then
      print("************************************")
      print("ERROR: ", err)
      print("************************************")
    end
    return 
  end

  counter = counter + 1
  if counter > 10 then
    -- wait all repspnses
    uv.timer():start(1000, function() cli:close() end)
    return
  end

  cli:write("Line #" .. counter .. "\n", on_write)
end

local function on_read(cli, err, data)
  if err then
    cli:close()
    if err:name() ~= "EOF" then
      print("************************************")
      print("ERROR: ", err)
      print("************************************")
    end
    return 
  end

  io.write(data)
end

local function on_connect(cli, err)
  if err then
    print("CONNECT:", err)
    return
  end

  cli:start_read(on_read)
  on_write(cli)
end


uv.pipe()
  :connect("\\\\.\\pipe\\sock.echo", on_connect)

uv.run()
