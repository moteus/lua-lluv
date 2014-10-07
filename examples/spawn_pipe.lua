local uv = require "lluv"

local stdout = uv.pipe()
local stderr = uv.pipe()
local stdin  = uv.pipe()

local function P(pipe, read)
  return {
    stream = pipe,
    flags = uv.CREATE_PIPE + 
            (read and uv.READABLE_PIPE or uv.WRITABLE_PIPE)
  }
end

local handle, err = uv.spawn({
  file = "cat",
  args = {},
  stdio = {P(stdin, true), P(stdout, false), P(stderr, false)}
}, function(...)
  print("exit:", ...)
end)

if not handle then
  print("Error spawn:", err)
  os.exit(-1)
end

print(handle, handle:pid())

stdout:start_read(function(...) print("stdout:", ...) end)

stderr:start_read(function(...) print("stderr:", ...) end)

stdin:write("Hello World", function(...)
  print("write: ", ...)
  stdin:shutdown(stdin.close)
end)

uv.run()
