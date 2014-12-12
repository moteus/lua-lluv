local uv = require "lluv"

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

  cli:write(data, on_write)
end

local function on_connection(srv, err)
  if err then
    print("LISTEN:", err)
    srv:close()
    return
  end
  local cli, err = srv:accept()
  if not cli then
    print("ACCEPT: ", err)
    return
  end
  cli:start_read(on_read)
end

uv.pipe()
:bind("\\\\.\\pipe\\sock.echo", function(srv, err, addr)
  if err then
    print("Can not bind:", tostring(err))
    return srv:close()
  end

  print("Bind on: " .. addr)
  srv:listen(on_connection)
end)

uv.run()
