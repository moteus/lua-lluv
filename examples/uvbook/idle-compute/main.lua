local uv = require "lluv"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr, stdout = io.stderr, io.stdout

local function crunch_away(handle, err)
  -- Compute extra-terrestrial life
  -- fold proteins
  -- computer another digit of PI
  -- or similar
  fprintf(stderr, "Computing PI...\n")
  -- just to avoid overwhelming your terminal emulator
  handle:stop()
end

local function on_type(file, err, buffer, size)
  if err then
    fprintf(stderr, "error opening file: %s\n", tostring(err))
    return
  end

  if size > 0 then
    fprintf(stdout, "Typed %s\n", buffer:to_s(size))
    file:read(buffer, -1, on_type)
  end
end

uv.idle()
  :start(crunch_away)

uv.fs_open_fd(0, true)
  :read(1024, -1, on_type)

return uv.run(debug.traceback)
