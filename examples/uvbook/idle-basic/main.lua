local uv = require "lluv"

local counter = 0

local function wait_for_a_while(handle, err)
  counter = counter + 1
  if counter >= 10e6 then
    handle:stop()
  end
end

local idler = uv.idle()

idler:start(wait_for_a_while)

print("Idling...")

uv.run()
