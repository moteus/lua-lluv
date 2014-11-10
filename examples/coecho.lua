local uv = require "lluv"
local ut = require "lluv.utils"

----------------------------------------------------------------------------
local CoSock = ut.class() do

local EOF = uv.error(uv.ERROR_UV, uv.EOF)

function CoSock:__init(s)
  self._co    = assert(coroutine.running())

  self._buf   = assert(ut.Buffer.new())

  self._timer = assert(uv.timer():start(1000,function(tm)
    tm:stop()
    self:_resume(nil, "timeout")
  end):stop())

  self._on_write = function(cli, err)
    self:_resume(not err, err)
  end

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

function CoSock:receive(pat)
  self:_start()
  self._wait_read = true

  while true do
    local msg = self._buf:read(pat)
    if msg then
      self._wait_read = false
      self:_stop()
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
  self._sock:connect(host, port, function(cli, err)
    if err then
      cli:close()
      self._sock = uv.tcp()
      return self:_resume(nil, err)
    end
    return self:_resume(true)
  end)

  local ok, err = self:_yield()
  if err == 'timeout' then
    self._sock:close()
    self._sock = uv.tcp()
  end

  if ok then self:_start_read() end

  return ok, err
end

function CoSock:settimeout(sec)
  if sec and (sec <= 0) then sec = nil end
  self._timeout = tonumber(sec)
  return self
end

function CoSock:close()
  if self._sock then
    self._sock:close(self._on_write)
    self._sock = nil
    return self._yield()
  end
  return true
end

function CoSock:__gc()
  if self._sock then
    self._sock:close()
    self._sock = nil
  end
end

end
----------------------------------------------------------------------------

----------------------------------------------------------------------------
local function CreateServer(ip, port, cb)

  local function on_connect(srv, err)
    if err then return cb(nil, err) end
    local cli, err = srv:accept()
    if not cli then cb(nil, err) end
    return cb(cli)
  end

  uv.tcp()
    :bind(ip, port)
    :listen(on_connect)
end
----------------------------------------------------------------------------

local echo_worker = function(sock, err)
  if not sock then return end

  local cli = CoSock.new(sock)

  cli:settimeout(5)

  while true do
    local msg, err = cli:receive()

    if msg then
      io.write(msg)
      cli:send(msg)
    else
      print("\n<ERROR> - ", err)
      if err ~= "timeout" then break end
    end

  end

  cli:close()
end

CreateServer("127.0.0.1", 5555, function(...)
  coroutine.wrap(echo_worker)(...)
end)

uv.run()