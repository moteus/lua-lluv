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

local function is_xxx(n)
  local a, b = n * 100, (n+1)*100
  return function(code)
    return (code >= a) and (code < b)
  end
end

local is_1xx = is_xxx(1)
local is_2xx = is_xxx(2)
local is_3xx = is_xxx(3)
local is_4xx = is_xxx(4)
local is_5xx = is_xxx(5)

local Error = ut.Errors{
  { EPROTO = "Protocol error" },
  { ESTATE = "Can not perform commant in this state" },
  { ECBACK = "Error while callink callback function" },
}
local EPROTO = Error.EPROTO
local ECBACK = Error.ECBACK

local function ErrorState(code, reply)
  local mt = {__index = Error(Error.ESTATE)}
  local err = setmetatable({}, mt)

  function err:code()
    return code
  end

  function err:reply()
    return reply
  end

  function err:is_1xx() return is_1xx(code) end

  function err:is_2xx() return is_2xx(code) end

  function err:is_3xx() return is_3xx(code) end

  function err:is_4xx() return is_4xx(code) end

  function err:is_5xx() return is_5xx(code) end

  local to_s = err.__tostring
  function mt:__tostring()
    local str = to_s(self)
    return string.format("%s\n%d %s", to_s(self), self:code(), self:reply())
  end

  return err
end

local WAIT = {}

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
      if is_1xx((ok())) then
        return ocall(req.cb_1xx, self, ok())
      end
    end

    assert(req == self._queue.pop())

    if ok then ocall(req.cb, self, nil, ok())
    else ocall(req.cb, self, err) end

    req = self._queue.peek()
  end
end

function Connection:_send(data, cb, cb_1xx)
  ocall(self.on_trace_control, self, data, true)
  self._cnn:write(data)
  self._queue.push{parser = ResponseParser:new(data), cb = cb, cb_1xx = cb_1xx, data = trim(data)}
  return self
end

function Connection:_command(...)
  local cmd, arg, cb, cb_1xx = ...
  if type(arg) == "function" then
    arg, cb, cb_1xx = nil, arg, cb
  end

  if arg then cmd = cmd .. " " .. arg end
  cmd = cmd .. EOL
  return self:_send(cmd, cb, cb_1xx)
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
do -- Implement FTP commands

local function on_greet(self, code, data, cb)
  if code == 220 and self._user then
    return self:auth(self._user, self._pass, cb)
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
  self:_command("PASV", function(self, err, code, reply)

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

local pasv_command_impl, pasv_exec_impl

local function pasv_dispatch_impl(self)
  if self._pasv_busy then return end

  local arg = self._pasv_pending.pop()
  if not arg then return end

  local cmd, arg, cb, chunk_cb = arg()
  self._pasv_busy = true
  
  if type(cmd) == "function" then
    return pasv_exec_impl(self, cmd)
  end
  return pasv_command_impl(self, cmd, arg, cb, chunk_cb)
end

pasv_command_impl = function(self, cmd, arg, cb, chunk_cb)
  return pasv(self, function(self, err, cli)
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

      if chunk_cb then
        local ok, err = pcall(chunk_cb, self, data)
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

pasv_exec_impl = function (self, cmd)
  return pasv(self, function(self, err, cli)
    if err then
      if cli then cli:close() end
      return cmd(self, err)
    end

    local ctx = {} do -- pasv context

    local ftp = self

    function ctx:error(err)
      cli:close()
      return self:_return(err)
    end

    function ctx:done(code, reply)
      if not is_2xx(code) then
        cli:close()
        return self:_return(nil, code, reply)
      end

      if self._done then
        return self:_return(nil, code, self._result or reply)
      end

      self._code, self._done = code, true
    end

    function ctx:_append(data)
      if not self._result then self._result = {} end
      self._result[#self._result + 1] = data
    end

    function ctx:_data()
      return self._result or true
    end

    function ctx:_return(...)
      ftp._pasv_busy = false
      pasv_dispatch_impl(ftp)
      return ocall(self.cb, ftp, ...)
    end

    end

    cli:start_read(function(cli, err, data)
      if err then
        cli:close()

        if err:name() == "EOF" then
          return ctx:done(ctx._code, ctx:_data())
        end

        return ctx:_return(err)
      end

      if ctx.chunk_cb then
        local ok, err = pcall(ctx.chunk_cb, self, data)
        -- @todo check error
      else ctx:_append(data) end
    end)

    cmd(self, nil, ctx)
  end)
end

local function pasv_command_(self, cmd, arg, cb, chunk_cb)
  -- passive mode require create send one extra req/rep and new connection
  -- so I think overhead to enqueue/dequeue is not too much.

  local callback = function(...)
    self._pasv_busy = false
    pasv_dispatch_impl(self)
    return ocall(cb, ...)
  end

  local args = va(cmd, arg, callback, chunk_cb)

  self._pasv_pending.push(args)

  return pasv_dispatch_impl(self)
end

local function pasv_command(self, cmd, ...)
  if type(...) == "string" then
    pasv_command_(self, cmd, ...)
  else
    pasv_command_(self, cmd, nil, ...)
  end
end

local function pasv_exec(self, cmd)
  local args = va(cmd)

  self._pasv_pending.push(args)

  return pasv_dispatch_impl(self)
end

-------------------------------------------------------------------

local function auth(self, uid, pwd, cb)
  self:_command("USER", uid, function(self, err, code, msg)
    if err then return ocall(cb, self, err) end
    if not is_3xx(code) then return ocall(cb, self, nil, code, msg) end
    self:_command("PASS", pwd, cb)
  end)
end

local function help(self, ...)
  self._command(self, "help", nil, ...)
end

local function pasv_list(self, ...)
  return pasv_command(self, "LIST", ...)
end

local function pasv_retr(self, fname, ...)
  assert(type(fname) == "string")

  local opt, cb = ...
  if type(opt) ~= "table" then
    return pasv_command(self, "RETR", fname, ...)
  end

  return pasv_exec(self, function(self, err, ctx)
    if err then return ocall(cb, self, err) end
    ctx.cb = cb
    if opt.sink then
      ctx.chunk_cb = function(self, chunk) return opt.sink(chunk) end
      ctx.cb       = function(...) opt.sink() return ocall(cb, ...) end
    elseif opt.reader then
      ctx.chunk_cb = opt.reader
    end

    -- @todo check result of command
    if opt.type then self:_command("TYPE", opt.type) end

    -- @todo check result of command
    if opt.rest then self:_command("REST", opt.rest) end

    self:_command("RETR", fname, function(self, err, code, data)
      if err then return ctx:error(err) end
      if is_1xx(code) then return end
      ctx:done(code, reply)
    end)
  end)
end

local function pasv_stor(self, fname, opt, cb)

  local write_cb
  if type(opt) == "table" then
    if opt.source then

      local on_write = function(cli, err)
        if err then
          cli:close()
          return ocall(cb, self, err)
        end
        return write_cb(self, cli)
      end

      write_cb = function(self, cli)
        local chunk = opt.source()
        if chunk then return cli:write(chunk, on_write) end
        return cli:close()
      end

    else
      write_cb = assert(opt.writer)
    end

    -- @todo check result of command
    if opt.type then self:_command("TYPE", opt.type) end

  else
    assert(type(opt) == "string")
    write_cb = function(self, cli)
      cli:write(opt, function(cli, err)
        cli:close()
        if err then return ocall(cb, self, err) end
      end)
    end
  end

  self:pasv(function(self, err, cli)
    if err then return ocall(cb, err) end

    
    self:_command("STOR", "test1.ttt", 
    -- command
    function(self, err, code, data)
      cli:close()
      if err then return ocall(cb, err) end
      return ocall(cb, err, code, data)
    end,
    -- write
    function(self, code, reply)
      write_cb(self, cli)
    end)
  end)

end

Connection.pasv = pasv
Connection.auth = auth
Connection.open = open
Connection.help = help
Connection.list = pasv_list
Connection.retr = pasv_retr
Connection.stor = pasv_stor

end
-------------------------------------------------------------------

local function run()
  local ltn12 = require "ltn12"

  local ftp = Connection:new("127.0.0.1:21", {
    uid = "moteus",
    pwd = "123456",
  })

  function ftp:on_error(err)
    print("<ERROR>", err)
  end

  function ftp:on_trace_control(line, send)
    print(send and "> " or "< ", trim(line))
    print("**************************")
  end

  function ftp:on_trace_req(req, code, reply)
    print("+", req.data, " GET ", code, reply)
  end

  ftp:open(function(self, err, code, data)
    if err then
      print("OPEN", err)
      return self:close()
    end

    -- self:list("test1.dat", function(self, err, code, data)
    --   print("LIST #1:", err, code, data)
    -- end)
    -- 
    -- self:retr("test1.dat", {type = "i", rest = 4}, function(self, err, code, data)
    --   print("RETR #1:", err, code, data)
    -- end)
    -- 
    -- self:list("test1.dat", function(self, err, code, data)
    --   print("LIST #2:", err, code, data)
    -- end)
    -- 
    -- self:retr("test1.dat", {type = "i", rest = 4}, function(self, err, code, data)
    --   print("RETR #2:", err, code, data)
    --   self:close()
    -- end)

    local src = ltn12.source.file(io.open("ftp.lua", "rb"))
    self:stor("ftp.lua", {source = src}, function(self, err, code, data)
      print("STOR ", err, code, data)
    end)

    local snk = ltn12.sink.file(io.open("test1.dat", "w+b"))
    self:retr("test1.dat", {type = "i", rest = 0, sink = snk}, function(self, err, code, data)
      print("RETR ", err, code, data)
      self:close()
    end)

  end)

  uv.run(debug.traceback)
end

run()

return {
  Connection = function(...) return Connection:new(...) end
}
