local uv = require "lluv"

local loop = uv.default_loop()

local counter = 0
uv.timer(loop):start(500, 1000, function(timer)
  print("Tick #" .. counter, timer, timer:loop())
  counter = counter + 1
  if counter == 10 then
    timer:close(function()
      print("Close")
    end)
  end
end)

local counter = 0
uv.timer():start(1000, function(timer)
  print("Tick #" .. counter, timer, timer:loop())
  counter = counter + 1
  if counter == 10 then
    timer:close(function(timer)
      print("Close:", timer)
    end)
  end
end)

uv.timer():start(4700, function(timer)

  timer:close(function(h)
    print("HClose:", h)
  end)

  timer:loop():handles(function(handle)
    -- if handle == timer then return end
    handle:close(function(h)
      print("WClose:", h)
    end)
  end)

end)

loop:run(debug.traceback)
