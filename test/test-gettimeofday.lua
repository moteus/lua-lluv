local uv  = require"lluv"

local function ver()
  local min, maj, pat = uv.version(true)
  return min * 100000 + maj * 100 + pat
end

if ver() < 102800 then
  print('Supported since 1.28.0. Got ' .. uv.version())
  return
end

io.write('gettimeofday - ')
local a, b = uv.gettimeofday()
if math.type then
  assert(math.type(a) == 'integer')
  assert(math.type(b) == 'integer')
else
  assert(type(a) == 'number')
  assert(type(b) == 'number')
end

assert(math.abs((os.time() - a)) < 100)
io.write('ok\n')
