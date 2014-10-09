local uv   = require "lluv"
local path = require "path"

local round_robin_counter = 0
local child_worker_count  = #uv.cpu_info()
local workers             = {}

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr = io.stderr

local function close_process_handle(handle, exit_status, term_signal)
  handle:close()

  for i, worker in ipairs(workers) do
    if worker.proc == handle then
      table.remove(workers, i)
      break
    end
  end

  fprintf(stderr, "Process exited with status %d, signal %d\n", exit_status, term_signal)

  child_worker_count = #workers

  if child_worker_count == 0 then
    fprintf(stderr, "All workers are dead.\n")
    uv.stop()
  end

end

local function on_new_connection(server, err)
  if err then
    fprintf(stderr, "Listen error: %s\n", tostring(err))
    return;
  end

  local cli, err = server:accept()
  if not cli then
    fprintf(stderr, "Accept error: %s\n", tostring(err))
    return
  end
  fprintf(stderr, "Accept : %s\n", cli:getsockname())

  round_robin_counter = round_robin_counter % child_worker_count + 1
  local worker = assert(workers[round_robin_counter], round_robin_counter)

  local ok, err = worker.pipe:write2(cli, function() cli:close() end)
  if not ok then
    fprintf(stderr, "Write2 error: %s\n", tostring(err))
    cli:close()
    return
  end
end

local function setup_workers(fname)
  local lua_path    = uv.exepath()
  local worker_path = path.join( path.currentdir(), fname)
  fprintf(stderr, "Lua path: %s\n",  lua_path);
  fprintf(stderr, "Worker path: %s\n", worker_path);

  for i = 1, #uv.cpu_info() do
    local worker = {
      pipe = uv.pipe(true),
    }

    worker.id = tostring(i)

    local err
    worker.proc, err = uv.spawn({
      file  = lua_path,
      args  = {worker_path, worker.id},
      stdio = {
        -- Windows fail create pipe in worker without `writable` flag
        { flags = {"create_pipe", "readable_pipe", "writable_pipe"};
          stream = worker.pipe;
        },
        {}, -- ignore
        2,  -- inherite fd
      }
    }, close_process_handle)

    if not worker.proc then
      worker.pipe:close()
      fprintf(stderr, "Spawn error: %s\n", tostring(err))
      os.exit(1)
    end

    workers[i] = worker
  end
end

----------------------------------------------------

setup_workers("worker.lua")

local server, err = uv.tcp():bind("0.0.0.0", 7000)

if not server then
  fprintf(stderr, "Bind error %s\n", tostring(err))
  return
end

local ok, err = server:listen(on_new_connection)

if not ok then
  fprintf(stderr, "Bind error %s\n", tostring(err))
  return
end

uv.run(debug.traceback);
