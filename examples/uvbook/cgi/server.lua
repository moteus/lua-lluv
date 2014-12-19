local uv   = require "lluv"
local path = require "path"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr = io.stderr

local function cleanup_handles(handle, err, exit_status, term_signal)
  local client = handle.data
  handle:close()
  client:close()

  if err then
    fprintf(stderr, "Spawn error %s\n", tostring(err))
  else
    fprintf(stderr, "Process exited with status %d, signal %d\n", exit_status, term_signal)
  end
end

local function invoke_cgi_script(client)
  local lua_path = uv.exepath()
  local cgi_path = path.join(path.currentdir(), "tick.lua")

  local process = uv.spawn({
    file  = lua_path,
    args  = {cgi_path},
    stdio = { {}, client }
  }, cleanup_handles)

  process.data = client
end

local function on_new_connection(server, err)
  if err then
    fprintf(stderr, "Listen error %s\n", tostring(err))
    return
  end

  local client, err = server:accept()
  if not client then
    fprintf(stderr, "Accept error %s\n", tostring(err))
    return
  end

  invoke_cgi_script(client)
end

uv.tcp():bind("*", 7000, function(srv, err, host, port)
  if err then
    fprintf(stderr, "Bind error %s\n", tostring(err))
    return
  end
  fprintf(stderr, "Bind on %s:%d\n", host, port)
  srv:listen(on_new_connection)
end)

return uv.run(debug.traceback)
