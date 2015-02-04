local uv     = require "lluv"
local ut     = require "lluv.utils"
local Socket = require "lluv.luasocket"

local SslSocket = ut.class(Socket._TcpSock) do

function SslSocket:__init(ctx, mode)
  self._ssl_ctx  = assert(ctx)
  self._ssl_mode = mode
  self._ssl_ctor = mode and ctx.server or ctx.client

  assert(SslSocket.__base.__init(self))

  self._sock:stop_read()
  return self
end

function SslSocket:_reset()
  if self._sock then self._sock:close() end
  self._sock = assert(self._ssl_ctor(self._ssl_ctx))
end

function SslSocket:connect(host, port)
  local ok, err = self:_connect(host, port)
  if not ok then return nil, err end
  return self:handshake()
end

function SslSocket:accept()
  local cli, err = self:_accept()
  if not cli then return nil, err end
  return cli:handshake()
end

function SslSocket:handshake()
  if not self._sock then return nil, self._err end

  local terminated
  self:_start("write")
  self._sock:handshake(function(cli, err)
    if terminated then return end
    if err then return self:_on_io_error(err) end
    return self:_resume(true)
  end)

  local ok, err = self:_yield()
  terminated = true
  self:_stop("write")

  if not ok then
    self._sock:stop_read()
    return nil, self._err
  end

  local ok, err = self:_start_read()
  if not ok then return nil, err end

  return self
end

function SslSocket:__tostring()
  return "lluv.ssl.luasocket (" .. tostring(self._sock) .. ")"
end

end

return {
  ssl = SslSocket.new
}
