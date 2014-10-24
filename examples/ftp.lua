-- FTP Client
-- This code is in development state and may be (and will) changed
------------------------------------------------------------------

local uv = require "lluv"
local ut = require "lluv.utils"
local va = require "vararg"

local EOL = "\r\n"

local usplit      = ut.usplit
local split_first = ut.split_first

local function trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function cb_args(...)
  local n = select("#", ...)
  local cb = va.range(n, n, ...)
  if type(cb) == 'function' then
    return cb, va.remove(n, ...)
  end
  return nil, ...
end

local function ocall(fn, ...) if fn then return fn(...) end end

local Error = ut.Errors{
  { EPROTO = "Protocol error" },
  { ESTATE = "Can not perform commant in this state" },
}
local EPROTO = Error.EPROTO

local function ErrorState(code, reply)
  local mt = {__index = Error(Error.ESTATE)}
  local err = setmetatable({}, mt)

  function err:ftp_code()
    return code
  end

  function err:ftp_reply()
    return reply
  end

  local to_s = err.__tostring
  function mt:__tostring()
    local str = to_s(self)
    return string.format("%s\n%d %s", to_s(self), self:ftp_code(), self:ftp_reply())
  end

  return err
end

local WAIT = {}

local function is_xxx(n)
  local a, b = n * 100, (n+1)*100
  return function(code)
    return (code >= a) and (code < b)
  end
end

local is_1xx = is_xxx(1)
local is_2xx = is_xxx(2)
local is_3xx = is_xxx(3)

-------------------------------------------------------------------
local ResponseParser = {} do
ResponseParser.__index = ResponseParser

function ResponseParser:new()
  local o = setmetatable({}, self)
  return o
end

function ResponseParser:next(buf) while true do
  local line = buf.next_line()
  if not line then return WAIT end

-- HELP:
-- 214-The following commands are recognized:
-- USER   PASS   QUIT   CWD    PWD    PORT   PASV   TYPE
-- LIST   REST   CDUP   RETR   STOR   SIZE   DELE   RMD
-- ...
-- 214 Have a nice day.

-- GREET
--220-FileZilla Server version 0.9.43 beta
--220-written by Tim Kosse (tim.kosse@filezilla-project.org)
--220 Please visit http://sourceforge.net/projects/filezilla/

  local resp, sep
  if self._resp then
    resp, sep = string.match(line, "^(" .. self._resp .. ")(.?)")
  else
    resp, sep = string.match(line, "^(%d%d%d)(.?)")
    if not resp then return nil, Error(EPROTO, line) end
    self._resp = resp
  end

  local msg 
  if not resp then msg = line
  else msg = line:sub(5) end

  if resp then
    if (sep == " ") or (sep == "") then -- end of response
      local res
      if self._data then
        if msg ~= "" then self._data[#self._data + 1] = msg end
        res = va(tonumber(resp), table.concat(self._data, "\n"))
      else
        res = va(tonumber(resp), msg)
      end
      self:reset()
      return res
    end
    if sep ~= "-" then return nil, Error(EPROTO, line) end
  end

  self._data = self._data or {}
  if msg ~= "" then self._data[#self._data + 1] = msg end
end end

function ResponseParser:reset()
  -- @todo check if preview state is done
  self._data = nil
  self._resp = nil
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local Connection = {} do
Connection.__index = Connection

function Connection:new(server, opt)
  local o = setmetatable({}, self)

  local host, port = usplit(server, ":")
  o._host  = host or "127.0.0.1"
  o._port  = port or "21"
  o._user  = opt.uid
  o._pass  = opt.pwd
  
  o._buff    = ut.Buffer(EOL)   -- pending data
  o._queue   = ut.Queue()       -- pending requests
  o._pasv_pending = ut.Queue()  -- passive requests

  return o
end

function Connection:connected()
  return not not self._cnn
end

function Connection:_open(cb)
  if self:connected() then return ocall(cb, self) end

  return uv.tcp():connect(self._host, self._port, function(cli, err)
    if err then
      cli:close()
      return ocall(cb, self, err)
    end

    cli.data = self
    self._cnn = cli
    self._buff.reset()
    self._queue.reset()
    self._pasv_pending.reset()

    self._queue.push{parser = ResponseParser:new(data), cb = cb}

    cli:start_read(function(cli, err, data)
      if err then
        self:close()
        return ocall(self.on_error, self, err)
      end
      return self:_read(data)
    end)

  end)
end

function Connection:close()
  if not self:connected() then return end
  self._cnn:close()
  self._cnn = nil
end

function Connection:_read(data)
  local req = self._queue.peek()
  if not req then -- unexpected reply
    self:close()
    return ocall(self.on_error, self, Error(EPROTO, data))
  end

  self._buff.append(data)

  ocall(self.on_trace_control, self, data, false)

  while req do
    local parser = req.parser
    local ok, err = parser:next(self._buff)
    if ok == WAIT then return end

    if ok then
      if self.on_trace_req then
        self:on_trace_req(req, ok())
      end
      if is_1xx(ok()) then return end
    end

    assert(req == self._queue.pop())

    if ok then ocall(req.cb, self, nil, ok())
    else ocall(req.cb, self, err) end

    req = self._queue.peek()
  end
end

function Connection:_send(data, cb)
  ocall(self.on_trace_control, self, data, true)
  self._cnn:write(data)
  self._queue.push{parser = ResponseParser:new(data), cb = cb, data = trim(data)}
  return self
end

function Connection:_command(...)
  local cb, cmd, arg = cb_args(...)
  if arg then cmd = cmd .. " " .. arg end
  cmd = cmd .. EOL
  return self:_send(cmd, cb)
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
do -- Implement FTP commands

local function auth(self, uid, pwd, cb)
  self:_command("USER", uid, function(self, err, code, msg)
    if err then return ocall(cb, self, err) end
    if not is_3xx(code) then return ocall(cb, self, nil, code, msg) end
    self:_command("PASS", pwd, cb)
  end)
end

local function on_greet(self, code, data, cb)
  if code == 220 and self._user then
    return auth(self, self._user, self._pass, cb)
  end
  return ocall(cb, self, code, data)
end

local function open(self, cb)
  return self:_open(function(self, err, code, greet)
    if err then
      if cb then return cb(self, err) end
      return self:close()
    end
    on_greet(self, code, data, cb)
  end)
end

local function pasv(self, cb)
  self:_command("PASV", uid, function(self, err, code, reply)

    if err then return ocall(cb, self, err) end

    if not is_2xx(code) then
      return ocall(cb, self, ErrorState(code, reply))
    end

    local pattern = "(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)"
    local _, _, a, b, c, d, p1, p2 = va.map(tonumber, string.find(reply, pattern))
    if not a then
      self:close()
      return ocall(cb, self, Error(EPROTO, data))
    end

    local ip, port = string.format("%d.%d.%d.%d", a, b, c, d), p1*256 + p2
    uv.tcp():connect(ip, port, function(cli, err)
      if err then
        cli:close()
        return ocall(cb, self, err)
      end
      return ocall(cb, self, nil, cli)
    end)

  end)
end

local function pasv_command_impl(self)

  if self._pasv_busy then return end

  local arg = self._pasv_pending.pop()
  if not arg then return end

  local cmd, arg, cb, chunk_cb = arg()
  self._pasv_busy = true

  pasv(self, function(self, err, cli)
    if err then
      if cli then cli:close() end
      return ocall(cb, self, err)
    end

    local result = chunk_cb and true or {}
    local done   = false
    local result_code

    cli:start_read(function(cli, err, data)
      if err then
        cli:close()

        if err:name() == "EOF" then
          if done then return ocall(cb, self, nil, result_code, result) end
          done = true
          return
        end

        return ocall(cb, self, err)
      end

      if chunk_cb then pcall(chunk_cb, self, data)
      else result[#result + 1] = data end
    end)

    self:_command(cmd, arg, function(self, err, code, reply)
      if err then
        cli:close()
        return ocall(cb, self, err)
      end

      if is_1xx(code) then return end

      if not is_2xx(code) then
        cli:close()
        return ocall(cb, self, nil, code, reply)
      end

      result_code = code

      if done then return ocall(cb, self, nil, result_code, result) end
      done = true
    end)
  end)
end

local function pasv_command_(self, cmd, arg, cb, chunk_cb)
  -- passive mode require create send one extra req/rep and new connection
  -- so I think overhead to enqueue/dequeue is not too much.

  local callback = function(...)
    self._pasv_busy = false
    pasv_command_impl(self)
    return ocall(cb, ...)
  end

  local args = va(cmd, arg, callback, chunk_cb)

  self._pasv_pending.push(args)

  return pasv_command_impl(self)
end

local function pasv_command(self, cmd, ...)
  if type(...) == "string" then
    pasv_command_(self, cmd, ...)
  else
    pasv_command_(self, cmd, nil, ...)
  end
end

local function help(self, ...)
  self._command(self, "help", nil, ...)
end

local function pasv_list(self, ...)
  return pasv_command(self, "LIST", ...)
end

local function pasv_retr(self, fname, ...)
  return pasv_command_(self, "RETR", fname, ...)
end

Connection.auth = auth
Connection.open = open
Connection.help = help
Connection.list = pasv_list
Connection.retr = pasv_retr

end
-------------------------------------------------------------------

local function run()

  local ftp = Connection:new("127.0.0.1:21", {
    uid = "user",
    pwd = "xxx",
  })

  function ftp:on_error(err)
    print("<ERROR>", err)
  end

  -- function ftp:on_trace_control(line, send)
  --   print(send and "> " or "< ", trim(line))
  --   print("**************************")
  -- end

  -- function ftp:on_trace_req(req, code, reply)
  --   print("+", req.data, " GET ", code, reply)
  -- end

  ftp:open(function(self, err, code, data)
    if err then
      print(err)
      return self:close()
    end
    print("OPEN: ", code, data)

    self:help(print)

    self:list(function(self, err)
      if err then print("LIST:", err) end
    end, function(self, data)
      io.write(data)
    end)

    self:retr("test1.dat", function(self, err, code, data)
      if err then return print("RETR:", err) end
      print("----------------------------------------")
      print("RETR")
      print("----------------------------------------")

      if is_2xx(code) then
        print(table.concat(data))
      else
        print(code, data)
      end

      self:close()
    end)
    self:_command("REST", 4)
  end)

  uv.run(debug.traceback)
end

run()

return {
  Connection = function(...) return Connection:new(...) end
}
