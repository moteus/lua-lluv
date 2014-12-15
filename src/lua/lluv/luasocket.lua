----------------------------------------------------------------------------
-- Implementation of LuaSocket interface.
--
-- Known wont fix problem:
--  - send does not return number of sended bytes
--  - send may not detects closed socket
--  - send do not wait until large data will be sended
----------------------------------------------------------------------------

local uv = require "lluv"
local ut = require "lluv.utils"

local function _check_resume(status, ...)
  if not status then return error(..., 3) end
  return ...
end

local function co_resume(...)
  return _check_resume(coroutine.resume(...))
end

local function CoGetAddrInfo(host, port)
  local co = assert(coroutine.running())
  local terminated = false

  uv.getaddrinfo(host, port, {
    family   = "inet";
    socktype = "stream";
    protocol = "tcp";
  }, function(_, err, res)
    if terminated then return end

    if err then co_resume(co, nil, err)
    else co_resume(co, res) end
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

  self._wait = {
    read   = false;
    write  = false;
    conn   = false;
    accept = false;
  }

  self._err = "closed"

  if s then
    self._sock = s
    self:_start_read()
  else
    self._sock  = assert(uv.tcp())
  end

  return self
end

function CoSock:_resume(...)
  return co_resume(self._co, ...)
end

function CoSock:_yield(...)
  return coroutine.yield(...)
end

function CoSock:_unset_wait()
  for k in pairs(self._wait) do self._wait[k] = false end
end

function CoSock:_waiting(op)
  if op then
    assert(nil ~= self._wait[op])
    return not not self._wait[op]
  end

  for k, v in pairs(self._wait) do
    if v then return true end
  end
end

function CoSock:_start(op)
  if self._timeout then
    self._timer:again(self._timeout * 1000)
  end

  self:_unset_wait()

  assert(self._wait[op] == false, op)
  self._wait[op] = true
end

function CoSock:_stop(op)
  if self._timer then
    self._timer:stop()
  end
  self:_unset_wait()
end

function CoSock:_on_io_error(err)
  if err == EOF then err = "closed" end

  self._err = err

  self._sock:close(function()
    if self:_waiting() then
      self:_resume(nil, err)
    end
  end)
  self._timer:close()
  self._sock, self._timer = nil
end

function CoSock:_start_read()
  self._sock:start_read(function(cli, err, data)
    if err then return self:_on_io_error(err) end

    if data then self._buf:append(data) end

    if self:_waiting("read") then return self:_resume(true) end
  end)
  return self
end

function CoSock:receive(pat, prefix)
  if not self._sock then return nil, self._err end

  if prefix and type(pat) == 'number' then
    pat = pat - #prefix
    if pat <= 0 then return prefix end
  end

  pat = pat or "*l"
  if pat == "*r" then pat = nil end

  self:_start("read")

  assert(self:_waiting("read"))

  if pat == "*a" then while true do
    local ok, err = self:_yield()

    if not ok then
      self:_stop("read")

      if err == 'timeout' then
        return nil, err, self._buf:read_all()
      end

      if err == 'closed' then
        return self._buf:read_all()
      end

      return nil, err
    end

  end end

  while true do
    local msg = self._buf:read(pat)
    if msg then
      self:_stop("read")
      if prefix then msg = prefix .. msg end
      return msg
    end

    local ok, err = self:_yield()
    if not ok then
      self:_stop("read")
      return nil, err, self._buf:read_all()
    end
  end
end

function CoSock:send(data)
  if not self._sock then return nil, self._err end

  local terminated
  self:_start("write")
  self._sock:write(data, function(cli, err)
    if terminated then return end
    if err then return self:_on_io_error(err) end
    return self:_resume(true)
  end)

  local ok, err = self:_yield()
  terminated = true
  self:_stop("write")

  if not ok then
    return nil, "closed"
  end
  return ok, err
end

function CoSock:connect(host, port)
  self:_start("conn")
  local res, err = CoGetAddrInfo(host, port)
  self:_stop("conn")

  if not res then return nil, err end

  local terminated, ok, err
  for i = 1, #res do
    self:_start("conn")

    self._sock:connect(res[i].address, res[i].port, function(cli, err)
      if terminated then return end
      return self:_resume(not err, err)
    end)

    ok, err = self:_yield()

    self:_stop("conn")

    if ok then break end

    self._sock:close()
    self._sock = uv.tcp()
  end
  terminated = true

  if not ok then return nil, err end

  return self:_start_read()
end

function CoSock:settimeout(sec)
  if sec and (sec <= 0) then sec = nil end
  self._timeout = tonumber(sec)
  return self
end

function CoSock:bind(host, port)
  if not self._sock then return nil, self._err end

  local ok, err = self._sock:bind(host, port)
  if not ok then
    self._sock:close()
    self._sock = uv.tcp()
    return nil, err
  end
  return self
end

local MAX_ACCEPT_COUNT = 10

function CoSock:_start_accept()
  if self._accept_list then return end

  self._accept_list = ut.Queue.new()

  self._sock:listen(function(srv, err)
    if err then return self:_on_io_error(err) end

    local cli, err = srv:accept()
    if not cli then return end

    while self._accept_list:size() > MAX_ACCEPT_COUNT do
      self._accept_list:pop():close()
    end

    self._accept_list:push(cli)

    if self:_waiting("accept") then
      return self:_resume(true, self._accept_list:pop())
    end
  end)

  return self
end

function CoSock:accept()
  if not self._sock then return nil, self._err end

  self:_start_accept()

  local cli = self._accept_list:pop()
  if not cli then
    self:_start("accept")
    local ok, err = self:_yield()
    self:_stop("accept")
    if not ok then return nil, err end
    cli = err
  end

  return CoSock.new(cli)
end

function CoSock:reset_co(co)
  assert(not self:_waiting())
  self._co = co or coroutine.running()
  return self
end

function CoSock:close()
  if self._sock  then self._sock:close()  end
  if self._timer then self._timer:close() end
  self._sock, self._timer = nil
  return true
end

CoSock.__gc = CoSock.close

function CoSock:setoption()
  return nil, "NYI"
end

function CoSock:getsockname()
  if not self._sock then return nil, self._err end

  return self._sock:getsockname()
end

function CoSock:getfd()
  if not self._sock then return -1 end
  return self._sock:fileno()
end

end
----------------------------------------------------------------------------

local function connect(host, port)
  local sok = CoSock.new()
  local ok, err = sok:connect(host, port)
  if not ok then
    sok:close()
    return nil, err
  end
  return sok
end

local function bind(host, port)
  local sok = CoSock.new()
  local ok, err = sok:bind(host, port)
  if not ok then
    sok:close()
    return nil, err
  end
  return sok
end

local SLEEP_TIMERS = {}

local function sleep(s)
  for co, timer in pairs(SLEEP_TIMERS) do
    if coroutine.status(co) == "dead" then
      timer:close()
      SLEEP_TIMERS[co] = nil
    end
  end

  if s <= 0 then return end

  local co = assert(coroutine.running())

  local timer = SLEEP_TIMERS[co]
  if not timer then
    timer = uv.timer():start(10000, function(self)
      self:stop()
      co_resume(co)
    end):stop()

    SLEEP_TIMERS[co] = timer
  end

  timer:again(math.floor(s * 1000))
  coroutine.yield()
end

uv.signal_ignore(uv.SIGPIPE)

return {
  tcp     = CoSock.new;
  connect = connect;
  bind    = bind;
  gettime = function() return math.floor(uv.now()/1000) end;
  sleep   = sleep;
}
