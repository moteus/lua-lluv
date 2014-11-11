local uv = require "lluv"
local ut = require "lluv.utils"

local function CoGetAddrInfo(host, port)
  local co = assert(coroutine.running())
  local terminated = false

  uv.getaddrinfo(host, port, {
    family   = "inet";
    socktype = "stream";
    protocol = "tcp";
  }, function(_, err, res)
    if terminated then return end

    if err then coroutine.resume(co, nil, err)
    else coroutine.resume(co, res) end
  end)

  local ok, err = coroutine.yield()
  terminated = true

  return ok, err 
end

----------------------------------------------------------------------------
local CoSock = ut.class() do

local EOF = uv.error(uv.ERROR_UV, uv.EOF)

function CoSock:__init(s)
  self._co    = assert(coroutine.running())

  self._buf   = assert(ut.Buffer.new("\r*\n", true))

  self._timer = assert(uv.timer():start(1000, function(tm)
    tm:stop()
    self:_resume(nil, "timeout")
  end):stop())

  self._on_write = function(cli, err) self:_resume(not err, err) end

  self._on_close = self._on_write

  if s then
    self._sock = s
    self:_start_read()
  else
    self._sock  = assert(uv.tcp())
  end

  return self
end

function CoSock:_resume(...)
  coroutine.resume(self._co, ...)
  return
end

function CoSock:_yield(...)
  return coroutine.yield(...)
end

function CoSock:_start()
  if self._timeout then
    self._timer:again(self._timeout * 1000)
  end
end

function CoSock:_stop()
  self._timer:stop()
end

function CoSock:_start_read()
  self._sock:start_read(function(cli, err, data)

    if err then
      self._sock = nil
      if err == EOF then err = "closed" end
      cli:close(function() self:_resume(nil, err) end)
      return
    end

    if data then self._buf:append(data) end

    if self._wait_read then
      return self:_resume(true)
    end

  end)
end

function CoSock:receive(pat, prefix)
  self:_start()
  self._wait_read = true

  pat = pat or "*l"
  if pat == "*r" then pat = nil end

  while true do
    local msg = self._buf:read(pat)
    if msg then
      self._wait_read = false
      self:_stop()
      if prefix then msg = prefix .. msg end
      return msg
    end

    local ok, err = self:_yield()
    if not ok then
      self._wait_read = false
      self:_stop()
      return nil, err
    end

  end
end

function CoSock:send(data)
  self:_start()
  self._sock:write(data, self._on_write)
  local ok, err = self:_yield()
  self:_stop()
  return ok, err
end

function CoSock:connect(host, port)
  self:_start()
  local res, err = CoGetAddrInfo(host, port)
  self:_stop()

  if not res then return nil, err end

  local ok, err
  for _, addr in ipairs(res) do
    self:_start()

    self._sock:connect(addr.address, addr.port, function(cli, err)
      if err then
        self._sock:close()
        self._sock = uv.tcp()
        return self:_resume(nil, err)
      end
      return self:_resume(true)
    end)

    ok, err = self:_yield()
    self:_stop()

    if ok then break end

    self._sock:close()
    self._sock = uv.tcp()
  end

  if not ok then return nil, err end
  self:_start_read()

  return self
end

function CoSock:settimeout(sec)
  if sec and (sec <= 0) then sec = nil end
  self._timeout = tonumber(sec)
  return self
end

function CoSock:close()
  if self._sock then
    self._sock:close(self._on_close)
    self._timer:close()
    self._sock, self._timer = nil
    return self:_yield()
  end
  return true
end

function CoSock:__gc()
  if self._sock then
    self._sock:close()
    self._timer:close()
    self._sock, self._timer = nil
  end
end

end
----------------------------------------------------------------------------

return {
  tcp = CoSock.new
}