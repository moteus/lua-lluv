local uv   = require "lluv"
local path = require "path"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr = io.stderr

local function invoke_cgi_script(client)
  local lua_path = uv.exepath()
  local cgi_path = path.join(path.currentdir(), "tick.lua")

  local function cleanup_handles(handle, exit_status, term_signal)
    handle:close()
    client:close()
    fprintf(stderr, "Process exited with status %d, signal %d\n", exit_status, term_signal)
  end

  --/* ... finding the executable path and setting up arguments ... */
  local child_req, err = uv.spawn({
    file  = lua_path,
    args  = {cgi_path},
    stdio = { {}, client }
  }, cleanup_handles)

  if not child_req then
    client:close()
    fprintf(stderr, "Spawn error %s\n", tostring(err))
    return;
  end

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

local ok, err = uv.tcp()
  :bind("0.0.0.0", 7000)
  :listen(on_new_connection)

if not ok then
  fprintf(stderr, "Listen error %s\n", tostring(err))
  return 1
end

return uv.run(debug.traceback)
