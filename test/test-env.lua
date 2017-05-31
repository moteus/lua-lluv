local uv = require "lluv"

if not uv.os_setenv then
  print('Skip - unsupported')
  return
end

local ok, err = uv.os_getenv('X')
assert(nil == ok)
assert(nil == err)

assert(uv.os_setenv('X', ('x'):rep(4096)))

ok, err = uv.os_getenv('X')
assert(ok == ('x'):rep(4096))

assert(uv.os_unsetenv('X'))

ok, err = uv.os_getenv('X')
assert(nil == ok)
assert(nil == err)

print("Home dir: ",  uv.os_homedir())
print("Host name: ", uv.os_gethostname())

print("Done!")