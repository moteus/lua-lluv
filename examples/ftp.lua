-- FTP Client
-- This code is in development state and may be (and will) changed
------------------------------------------------------------------

-- Usage:

-- local ftp = Ftp.new("127.0.0.1:21",{
--   uid = "moteus",
--   pwd = "123456",
-- })
-- 
-- ftp:open(function(self, err)
--   assert(not err, tostring(err))
--   self:mkdir("sub") -- ignore error
--   self:store("sub/test.txt", "Some data", function(self, err)
--     assert(not err, tostring(err))
--   end)
-- end)

local uv = require "lluv"
local ut = require "lluv.utils"
local va = require "vararg"

local EOL = "\r\n"

local class       = ut.class
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

local function is_err(n) return is_4xx(n) or is_5xx(n) end

local Error = ut.Errors{
  { EPROTO = "Protocol error" },
  { ESTATE = "Can not perform commant in this state" },
  { ECBACK = "Error while callink callback function" },
}
local EPROTO = Error.EPROTO
local ECBACK = Error.ECBACK

-------------------------------------------------------------------
local ErrorState do

local EState = class(Error.__class) do

function EState:__init(code, reply)
  self.__base.__init(self, "ESTATE")
  self._code  = code
  self._reply = reply
  return self
end

function EState:code()   return self._code         end

function EState:reply()  return self._reply        end

function EState:is_1xx() return is_1xx(self._code) end

function EState:is_2xx() return is_2xx(self._code) end

function EState:is_3xx() return is_3xx(self._code) end

function EState:is_4xx() return is_4xx(self._code) end

function EState:is_5xx() return is_5xx(self._code) end

function EState:__tostring()
  local str = self.__base.__tostring(self)
  return string.format("%s\n%d %s", str, self:code(), self:reply())
end

end

ErrorState = function(...)
  return EState.new(...)
end

end
-------------------------------------------------------------------

print(ErrorState(200, "OK"))

do return end

local WAIT = {}

-------------------------------------------------------------------
local ResponseParser = class() do

function ResponseParser:next(buf) while true do
  local line = buf:next_line()
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
      self:append(msg)

      local resp = tonumber(resp)
      local data = self._data
      self:reset()

      if is_err(resp) then
        if type(data) == "table" then data = table.concat(data, "\n") end
        return nil, ErrorState(resp, data)
      end

      return va(resp, data)
    end
    if sep ~= "-" then return nil, Error(EPROTO, line) end
  end

  self:append(msg)
end end

function ResponseParser:reset()
  -- @todo check if preview state is done
  self._data = nil
  self._resp = nil
end

function ResponseParser:append(msg)
  if msg == "" then return end

  if self._data then
    if type(self._data) == "string" then
      self._data = {self._data, msg}
    else
      self._data[#self._data + 1] = msg
    end
  else
    self._data = msg
  end
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local Connection = class() do
Connection.__index = Connection

function Connection:__init(server, opt)
  local host, port = usplit(server, ":")
  self._host  = host or "127.0.0.1"
  self._port  = port or "21"
  self._user  = opt.uid
  self._pass  = opt.pwd
  
  self._buff         = ut.Buffer.new(EOL) -- pending data
  self._queue        = ut.Queue.new()     -- pending requests
  self._pasv_pending = ut.Queue.new()     -- passive requests

  return self
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
    self._buff:reset()
    self._queue:reset()
    self._pasv_pending:reset()

    self._queue:push{parser = ResponseParser:new(), cb = cb}

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
  local req = self._queue:peek()
  if not req then -- unexpected reply
    self:close()
    return ocall(self.on_error, self, Error(EPROTO, data))
  end

  self._buff:append(data)

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

    assert(req == self._queue:pop())

    if ok then ocall(req.cb, self, nil, ok())
    else ocall(req.cb, self, err) end

    req = self._queue:peek()
  end
end

function Connection:_send(data, cb, cb_1xx)
  ocall(self.on_trace_control, self, data, true)
  self._cnn:write(data)
  self._queue:push{parser = ResponseParser:new(data), cb = cb, cb_1xx = cb_1xx, data = trim(data)}
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

  local arg = self._pasv_pending:pop()
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

    function ctx:data_done(err)
      cli:close()

      -- we already had control done
      if self._ctr_done then
        return self:_return(err, self._code, self._result)
      end

      -- indicate io done
      self._io_done, self._io_err = true, err
    end

    function ctx:control_done(err, code, reply)
      -- we had data_done
      if self._io_done then
        return self:_return(err or self._io_err or nil, code, self._result or reply)
      end

      -- indicate control done
      self._ctr_done, self._code, self._result = true, code, self._result or reply

      -- we get error via control channel
      if err then self:data_done(err) end
    end

    function ctx:get_cli() return cli end

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
        if err:name() == "EOF" then
          return ctx:data_done()
        end
        return ctx:data_done(err)
      end

      if ctx.chunk_cb then
        -- @todo check error
        local ok, err = pcall(ctx.chunk_cb, self, data)
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

  self._pasv_pending:push(args)

  return pasv_dispatch_impl(self)
end

local function pasv_command(self, cmd, ...)
  if type(...) == "function" then
    pasv_command_(self, cmd, nil, ...)
  else
    pasv_command_(self, cmd, ...)
  end
end

local function pasv_exec(self, cmd)
  local args = va(cmd)

  self._pasv_pending:push(args)

  return pasv_dispatch_impl(self)
end

-------------------------------------------------------------------

local function auth(self, uid, pwd, cb)
  self:_command("USER", uid, function(self, err, code, reply)
    if err then return ocall(cb, self, err) end
    if not is_3xx(code) then return ocall(cb, self, nil, code, reply) end
    self:_command("PASS", pwd, cb)
  end)
end

local function help(self, arg, cb)
  if not cb then arg, cb = nil, arg end
  assert(cb)
  self._command(self, "HELP", arg, function(self, err, code, data)
    if err then
      if arg then
        -- check if command not supported
        if err:no() == Error.ESTATE and err:code() == 502 then
          return cb(self, nil, false, err)
        end
      end
      return cb(self, err)
    end
    if type(data) == "table" then
      if #data > 1 then table.remove(data, 1) end
      if #data > 1 then table.remove(data, #data) end
      if not arg then -- return list of commands
        local t = {}
        data = ut.split(trim(table.concat(data, " ")), "%s+")
      else
        if #data == 1 then data = data[1] end
      end
    end
    cb(self, nil, data)
  end)
end

local function noop(self, cb)
  self._command(self, "NOOP", cb)
end

local trim_code = function(cb)
  return function(self, err, code, data)
    if not err then return cb(self, nil, data) end
    return cb(self, err, code, data)
  end
end

local ret_true = function(cb)
  return function(self, err, code, data)
    if err then return cb(self, err, code, data) end
    return cb(self, nil, true)
  end
end

local function cwd(self, arg, cb)
  assert(arg)
  assert(cb)
  self._command(self, "CWD", arg, ret_true(cb))
end

local function pwd(self, cb)
  assert(cb)
  self._command(self, "PWD", trim_code(cb))
end

local function mdtm(self, arg, cb)
  assert(arg)
  assert(cb)
  self._command(self, "MDTM", arg, trim_code(cb))
end

local function mkd(self, arg, cb)
  assert(arg)
  assert(cb)
  self._command(self, "MKD", arg, trim_code(cb))
end

local function hash(self, arg, cb)
  assert(arg)
  assert(cb)
  self._command(self, "HASH", arg, cb)
end

local function rename(self, fr, to, cb)
  assert(fr)
  assert(to)
  assert(cb)
  self._command(self, "RNFR", fr, function(self, err, code, data)
    if err then return cb(self, err, code, data) end
    assert(code == 350)
    self._command(self, "RNTO", to, cb)
  end)
end

local function rmd(self, arg, cb)
  assert(cb)
  assert(arg)
  self._command(self, "RMD", arg, ret_true(cb))
end

local function dele(self, arg, cb)
  assert(cb)
  assert(arg)
  self._command(self, "DELE", arg, ret_true(cb))
end

local function size(self, arg, cb)
  assert(cb)
  assert(arg)
  self._command(self, "SIZE", arg, function(self, err, code, data)
    if err then return cb(self, err) end
    return cb(self, nil, tonumber(data) or data)
  end)
end

local function file_not_found(err)
  return err:no() == Error.ESTATE and err:code() == 550
end

local list_cb = function(cb)
  return function(self, err, code, data)
    if err then
      if file_not_found(err) then return cb(self, nil, {}, err) end
      return cb(self, err)
    end
    cb(self, nil, ut.split(table.concat(data), EOL, true))
  end
end

local function stat(self, arg, cb)
  if not cb then arg, cb = nil, arg end
  assert(cb)
  self._command(self, "STAT", arg, function(self, err, code, list)
    if err then
      if file_not_found(err) then return cb(self, nil, {}, err) end
      return cb(self, err)
    end
    if #list > 1 then table.remove(list, 1) end
    if #list > 1 then table.remove(list, #list) end
    cb(self, err, list)
  end)
end

local function pasv_list(self, arg, cb)
  if not cb then arg, cb = nil, arg end
  assert(cb)
  return pasv_command(self, "LIST", arg, list_cb(cb))
end

local function pasv_nlst(self, arg, cb)
  if not cb then arg, cb = nil, arg end
  assert(cb)
  return pasv_command(self, "NLST", arg, list_cb(cb))
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
      return ctx:control_done(err, code, data)
    end)
  end)
end

local function pasv_stor(self, fname, opt, cb)
  pasv_exec(self, function(self, err, ctx)

    local write_cb, data
    if type(opt) == "table" then
      if opt.source then

        local on_write = function(cli, err)
          if err then return ctx:data_done(err) end
          return write_cb(self, cli)
        end

        write_cb = function(self, cli)
          local chunk = opt.source()
          if chunk then return cli:write(chunk, on_write) end
          return ctx:data_done()
        end

      else
        write_cb = assert(opt.writer)
      end
    else
      assert(type(opt) == "string")
      local data data, opt = opt, {}
      write_cb = function(self, cli)
        cli:write(data, function(cli, err)
          ctx:data_done(err)
        end)
      end
    end

    if err then return ocall(cb, err) end

    local cli = ctx:get_cli()
    ctx.cb = cb

    -- @todo check result of command
    if opt.type then self:_command("TYPE", opt.type) end

    self:_command("STOR", fname, 
      -- command
      function(self, err, code, data)
        return ctx:control_done(err, code, data)
      end,
  
    -- write
    function(self, code, reply)
      write_cb(self, cli)
    end)
  end)
end

-- This is Low Level commands
Connection.command       = Connection._command
Connection.pasv          = pasv
Connection.pasv_command  = pasv_command
Connection.pasv_exec     = pasv_exec

-- Open connection to ftp
Connection.open   = open

-- Specific ftp commands
Connection.noop   = noop
Connection.help   = help
Connection.auth   = auth
Connection.chdir  = cwd
Connection.cwd    = cwd
Connection.pwd    = pwd
Connection.mdtm   = mdtm
Connection.hash   = hash
Connection.rename = rename
Connection.rmdir  = rmd
Connection.rmd    = rmd
Connection.remove = dele
Connection.dele   = dele
Connection.mkd    = mkd
Connection.mkdir  = mkd
Connection.size   = size
Connection.stat   = stat
Connection.list   = pasv_list
Connection.nlst   = pasv_nlst
Connection.retr   = pasv_retr
Connection.stor   = pasv_stor

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

  -- function ftp:on_trace_req(req, code, reply)
  --   print("+", req.data, " GET ", code, reply)
  -- end

  ftp:open(function(self, err, code, data)
    if err then
      print("OPEN FAIL: ", err)
      return self:close()
    end

    self:mdtm("test1.dat", print)

    self:mkdir("sub1", print)

    self:rmdir("sub1", print)

    self:help(function(self, err, list)
      if err then return print("HELP #1:", err) end
      if type(list) == "table" then -- server return list of commands
        for k, v in ipairs(list) do
          print(k, v)
        end
      else
        -- server return just message e.g. `214 For help, please visit ...`
        print(list)
      end
      print("HELP #1: done")
    end)

    self:help("RETR", print)

    self:stat("test1.dat", function(self, err, list)
      if err then return print("STAT #1:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("STAT #1: done")
    end)

    self:stat(function(self, err, list)
      if err then return print("STAT #2:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("STAT #2: done")
    end)

    self:rename("test1.dat", "testx.dat", print)

    self:noop()

    self:rename("testx.dat", "test1.dat", print)

    self:noop()

    self:list("test1.dat", function(self, err, list)
      if err then return print("LIST #1:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("LIST #1: done")
    end)

    self:list("test12.dat", function(self, err, list)
      if err then return print("LIST #2:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("LIST #2: done")
    end)

    self:list(function(self, err, list)
      if err then return print("LIST #3:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("LIST #3: done")
    end)

    self:list("/sub", function(self, err, list)
      if err then return print("LIST #4:", err) end
      for k, v in ipairs(list) do
        print(k, v)
      end
      print("LIST #4: done")
    end)

    self:retr("test1.dat", {type = "i", rest = 4}, function(self, err, code, data)
      print("RETR #1:", err, code, data)
    end)

    self:list("test1.dat", function(self, err, code, data)
      print("LIST #2:", err, code, data)
    end)

    self:retr("test1.dat", {type = "i", rest = 4}, function(self, err, code, data)
      print("RETR #2:", err, code, data)
    end)

    local src = ltn12.source.file(io.open("ftp.lua", "rb"))
    self:stor("ftp.lua", {type = "i", source = src}, function(self, err, code, data)
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
