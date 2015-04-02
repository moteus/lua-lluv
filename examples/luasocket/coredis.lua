-- using `redis-lua` library

local redis  = require "redis"
local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"

ut.corun(function()
  local client = redis.connect{
    socket = assert(socket.connect("127.0.0.1", 6379))
  }

  print(client:select(15))

  -- basic
  client:set('foo', 'bar')
  print(client:get('foo'))

  print("----------------------------------")

  -- pipeline
  local replies = client:pipeline(function(p)
    p:ping()
    p:flushdb()
    p:exists('counter')
    p:incrby('counter', 10)
    p:incrby('counter', 30)
    p:exists('counter')
    p:get('counter')
    p:mset({ foo = 'bar', hoge = 'piyo'})
    p:del('foo', 'hoge')
    p:mget('does_not_exist', 'counter')
    p:info()
  end)

  for _, reply in pairs(replies) do
      print('*', reply)
  end

  client:quit()
end)

uv.run()
