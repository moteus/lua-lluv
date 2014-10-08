local uv = require "lluv"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr = io.stderr

local function on_read(client, err, data)
  if err then
    if err:no() ~= uv.EOF then
      fprintf(stderr, "Read error %s\n", tostring(err))
    end
    return client:close()
  end

  fprintf(stderr, "%s", data)
end

local function on_connect(cli, err)
  if err then
    fprintf(stderr, "connect failed error %s\n", tostring(err))
    return
  end

  cli:start_read(on_read)
end

local function on_resolved(loop, err, res)
  if err then
    fprintf(stderr, "getaddrinfo callback error %s\n", tostring(err))
    return
  end

  fprintf(stderr, "%s:%d\n", res[1].address, res[1].port)

  uv.tcp():connect(res[1].address, res[1].port, on_connect)
end

fprintf(stderr, "irc.freenode.net is... ")

uv.getaddrinfo("irc.freenode.net", 6667, {
  family   = "inet";
  socktype = "stream";
  protocol = "tcp";
}, on_resolved)

uv.run(debug.traceback)