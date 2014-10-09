local uv   = require "lluv"
local path = require "path"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr, stdout = io.stderr, io.stdout

function on_exit(handle, exit_status, term_signal)
  fprintf(stderr, "Process exited with status %d, signal %d\n", exit_status, term_signal);
  handle:close()
end

local lua_path = uv.exepath()

local tst_path = path.join(path.currentdir(), "test.lua")

local ok, err = uv.spawn({
  file  = lua_path;
  args  = {tst_path};
  stdio = { {}, {}, 2 };
}, on_exit)

if not ok then
  fprintf(stderr, "%s\n", tostring(err));
end

return uv.run()

