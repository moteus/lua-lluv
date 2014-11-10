local uv = require "lluv"

local worker = function(name)
  local co = assert(coroutine.running())

  local resume = function(...) return coroutine.resume(co, ...) end

  local sleep do
    local sleep_timer = uv.timer():start(10000, function(self)
      self:stop()
      resume()
    end):stop()

    sleep = function(ms)
      sleep_timer:again(ms)
      coroutine.yield()
    end
  end

  for i = 1, 10 do
    print(name, " - ", i)
    sleep(200 * i)
  end

end

coroutine.wrap(worker)("Worker #1")

coroutine.wrap(worker)("Worker #2")

uv.run()
