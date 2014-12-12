local RUN = lunit and function()end or function ()
  local res = lunit.run()
  if res.errors + res.failed > 0 then
    os.exit(-1)
  end
  return os.exit(0)
end

local lunit      = require "lunit"
local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end

local uv     = require "lluv.unsafe"

local ENABLE = true

local _ENV = TEST_CASE'defer_error' if ENABLE then

local it = setmetatable(_ENV or _M, {__call = function(self, describe, fn)
  self["test " .. describe] = fn
end})

function setup()
  sock = assert(uv.udp())
end

function teardown()
  sock:close()
  uv.run("once")
end

it("should raise error", function()
  assert_error(function() sock:send("798897", 12, "hello") end)
  uv.run()
end)

it("should call callback", function()
  local flag = false
  assert_pass(function()
    sock:send("798897", 12, "hello", function(s, e)
      flag = true
      assert_equal(sock, s)
      assert(e)
      assert_equal("798897:12", e:ext())
    end)
  end)
  assert_false(flag)
  uv.run()
  assert_true(flag)
end)

end

RUN()
