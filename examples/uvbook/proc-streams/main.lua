local uv   = require "lluv"
local path = require "path"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr, stdout = io.stderr, io.stdout

function on_exit(handle, err, exit_status, term_signal)
  if err then
    fprintf(stderr, "%s\n", tostring(err))
  else
    fprintf(stderr, "Process exited with status %d, signal %d\n", exit_status, term_signal)
  end
  handle:close()
end

local lua_path = uv.exepath()

local tst_path = path.join(path.currentdir(), "test.lua")

uv.spawn({
  file  = lua_path;
  args  = {tst_path};
  stdio = { {}, {}, 2 };
}, on_exit)

return uv.run()

