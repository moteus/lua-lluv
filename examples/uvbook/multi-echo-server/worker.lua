local uv   = require "lluv"
local path = require "path"

local fprintf = function(f, ...) f:write((string.format(...))) end
local stderr = io.stderr
local WORKER_ID = assert(tonumber(arg[1]))

local function echo_write(client, err)
  if err then
    fprintf(stderr, "Write error %s\n", tostring(err));
  end
end

local function echo_read(client, err, data)
  if err then
    if err:no() ~= uv.EOF then
      fprintf(stderr, "Read error %s\n", tostring(err))
    end
    return client:close()
  end

  client:write(data, echo_write)
end

local function on_new_connection(pipe, err, data)
  if err then
    if err:no() ~= uv.EOF then
      fprintf(stderr, "Read error %s\n", tostring(err))
    end
    return pipe:close()
  end

  local c = 0
  while(pipe:pending_count() > 0)do
    local cli, err = pipe:accept()
    if not cli then
      fprintf(stderr, "Accept fail: %s\n", tostring(err));
      return;
    end
    fprintf(stderr, "Worker %d: Accepted fd %s\n", WORKER_ID, "X");
    cli:start_read(echo_read)
    c = c + 1
  end

  if c == 0 then
    fprintf(stderr, "No pending count\n")
  end

  fprintf(stderr, "Connection data: %s", data)
end

------------------------------------------------------------

local queue = uv.pipe(true)
local ok, err = queue:open(0)
if not ok then
  fprintf(stderr, "Queue open error %s\n", tostring(err))
  os.exit(1)
end
queue:start_read(on_new_connection)

uv.run(debug.traceback)
