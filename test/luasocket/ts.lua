local socket = require("socket");
local host = host or "127.0.0.1";
local port = port or "8384";

server = assert(socket.bind(host, port));

while true do
  print("server: waiting for client connection...")
  local control = assert(server:accept())
  socket.sleep(0.5)
  control:close()
end
