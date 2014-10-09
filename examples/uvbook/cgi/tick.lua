local socket = require "socket"

for i = 1, 10 do
  print("tick")
  io.stdout:flush()
  socket.sleep(1)
end

print("BOOM!")
