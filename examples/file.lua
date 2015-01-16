local uv = require "lluv"

local chunk_size = 10

local file_name = "test.txt"

local function on_close()
  print("Close:", file_name)
  os.remove(file_name)
  print("Remove:", file_name)
end

local offset = 0
local function on_read_data(file, err, buf, size)
  print("Read:", err or (size==0) and "EOF" or size)

  -- error
  if err or size == 0 then
    file:close(on_close)
    if buf then buf:free() end
    return
  end

  assert(buf:size() == chunk_size)
  assert(buf:size() >= size      )

  offset = offset + size

  print(buf:to_s(size))
  file:read(buf, offset, on_read_data)
end

local function on_open(file, err, path)
  print("Open:", path, err or file)
  if err then return end
  file:read(chunk_size, on_read_data)
end

uv.fs_open(file_name, "w+", function(file, err, path)
  print("Create:", path, err or file)
  if err then return end
  file:write(("0123456789"):rep(3) .. "012345")
  print("Write test data")
  file:close(function()
    print("Close:", path)
    uv.fs_open(path, "r+", on_open)
  end)
end)

uv.run(debug.traceback)
