local uv   = require "lluv"
local path = require "path"

local TEST_PORT = 5555

local WRITE_REQ_DATA  = "Hello, world."

local NUM_WRITE_REQS  = (1000 * 1000)

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr, stdout = io.stderr, io.stdout

local tcp_client

local shutdown_cb_called = 0;
local connect_cb_called = 0;
local write_cb_called = 0;
local close_cb_called = 0;

local connect_cb
local write_cb
local shutdown_cb
local close_cb

function connect_cb(handle, err)
  assert(handle == tcp_client)
  assert(not err, tostring(err))

  start = uv.hrtime()

  for i = 1, NUM_WRITE_REQS do
    handle:write(WRITE_REQ_DATA, write_cb)
  end

  handle:shutdown(shutdown_cb)

  connect_cb_called = connect_cb_called + 1
end

function write_cb(handle)
  assert(handle == tcp_client)
  assert(not err, tostring(err))

  write_cb_called = write_cb_called + 1
end

function shutdown_cb(handle, err)
  assert(handle == tcp_client)
  assert(not err, tostring(err))

  -- todo?
  -- assert(handle:write_queue_size() == 0)

  handle:close(close_cb)

  shutdown_cb_called = shutdown_cb_called + 1
end

function close_cb(handle)
  assert(handle == tcp_client)
  close_cb_called = close_cb_called + 1
end

function tcp_write_batch()

  local process = uv.spawn({
    file  = uv.exepath();
    args  = {"tcp_sink.lua"};
    cwd   = uv.cwd();
    stdio = {{}, 1, 2};
  }, function()
    print("server closed")
  end):unref()

  tcp_client = uv.tcp()
    :connect("127.0.0.1", TEST_PORT, connect_cb)


  uv.run()

  stop = uv.hrtime()

  process:ref():kill()

  while uv.run("once") == 1 do end

  assert(connect_cb_called  == 1)
  assert(write_cb_called    == NUM_WRITE_REQS)
  assert(shutdown_cb_called == 1)
  assert(close_cb_called    == 1)

  fprintf(stdout, "ld write requests in %.2fs.\n",
         NUM_WRITE_REQS,
         (stop - start) / 1e9);

  return 0
end

tcp_write_batch()
