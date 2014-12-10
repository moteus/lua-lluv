local zmq = require "lzmq"
local uv  = require "lluv"

local sock = zmq.context():socket{"SUB",
  subscribe = "", connect = "tcp://127.0.0.1:5555";
}

local function on_new_message(msg)
  print(msg)
end

uv.poll_socket(sock:fd()):start(function(handle, err, event)
  if err then
    print("Poll error: ", err)
    return uv.stop()
  end

  -- with zmq we must read all avaliable messages
  while sock:has_event(zmq.POLLIN) do
    local msg, err = sock:recvx()
    if not msg then
      print("Recv error : ", err)
      return
    end
    on_new_message(msg)
  end
end)

uv.run()
