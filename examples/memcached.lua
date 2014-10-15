--
--[[-- usage
local umc = mc.Connection("127.0.0.1:11211")

umc:open(function(err)
  if err then return print(err) end

  for i = 1, 10 do
    umc:set("test_key", "test_value " .. i, 10, function(err, result)
      print("Set #" .. i, err, result)
    end)

    umc:get("test_key", function(err, value)
      print("Get #" .. i, err, value)
    end)
  end

  umc:get("test_key", function(err, value) umc:close() end)
end)

uv.run(debug.traceback)
]]

local uv = require "lluv"
local va = require "vararg"
local ut = require "utils"

local EOL = "\r\n"

local REQ_STORE      = 0 -- single line response
local REQ_RETR       = 1 -- line + data response
local REQ_RETR_MULTI = 2 -- line + data response (many keys)

local SERVER_ERRORS = {
  ERROR        = true;
  CLIENT_ERROR = true;
  SERVER_ERROR = true
}

local STORE_RESP = {
  STORED        = true;
  NOT_STORED    = true;
  EXISTS        = true;
  NOT_EXISTS    = true;
}

local ocall       = ut.ocall
local usplit      = ut.usplit
local split_first = ut.split_first

local function cb_args(...)
  local n = select("#", ...)
  local cb = va.range(n, n, ...)
  if type(cb) == 'function' then
    return cb, va.remove(n, ...)
  end
  return nil, ...
end

-------------------------------------------------------------------
local Error = {} do
Error.__index = Error

function Error:new(err)
  local o = setmetatable({}, self)
  o._err = err
  return o
end

function Error:__tostring()
  return self._err
end

end
-------------------------------------------------------------------

local function make_store(cmd, key, data, exptime, flags, noreply, cas)
  assert(cmd)
  assert(key)
  assert(data)

  if type(data) == "number" then data = tostring(data) end

  exptime = exptime or 0
  noreply = noreply or false
  flags   = flags   or 0

  local buf = { cmd, key, flags or 0, exptime or 0, #data, cas}

  if noreply then buf[#buf + 1] = "noreply" end

  return table.concat(buf, " ") .. EOL ..  data .. EOL
end

local function make_retr(cmd, key)
  assert(cmd)
  assert(key)
  return cmd .. " " .. key .. EOL
end

-------------------------------------------------------------------
local Connection = {} do
Connection.__index = Connection

function Connection:new(server)
  local o = setmetatable({}, self)

  local host, port = usplit(server, ":")
  o._host  = host or "127.0.0.1"
  o._port  = port or "11211"
  o._buff  = ut.Buffer(EOL) -- pending data
  o._queue = ut.Queue()     -- pending requests

  return o
end

function Connection:connected()
  return not not self._cnn
end

function Connection:open(cb)
  if self:connected() then return ocall(cb) end
  return uv.tcp():connect(self._host, self._port, function(cli, err)
    if err then
      cli:close()
      return ocall(cb, err)
    end
    cli.data = self
    self._cnn = cli
    cli:start_read(function(cli, err, data)
      if err then
        self:close()
        return ocall(self.on_error, self, err)
      end
      return self:_read(data)
    end)
    return ocall(cb)
  end)
end

function Connection:close()
  if not self:connected() then return end
  self._cnn:close()
  self._cnn = nil
end

function Connection:on_error(err) end

function Connection:_read(data)
  local req = self._queue.peek()
  if not req then -- unexpected reply
    self:close()
    return ocall(self.on_error, self, Error:new("Protocol error"))
  end

  while req do
    if req.type == REQ_STORE then
      local line = self._buff.next_line(data)
      if not line then return end
      assert(self._queue.pop() == req)

      if STORE_RESP[line] then
        ocall(req.cb, nil, line)
      else
        local res, value = split_first(line, " ", true)
        if SERVER_ERRORS[res] then
          ocall(req.cb, Error:new(line))
        else
          self:close()
          return ocall(self.on_error, self, Error:new("Protocol error"))
        end
      end
      
    elseif req.type == REQ_RETR then

      if not req.len then -- we wait next data
        local line = self._buff.next_line(data)
        if not line then return end
        data = ""

        if line == "END" then -- no more data
          assert(self._queue.pop() == req)

          if req.multi then
            ocall(req.cb, nil, req.res)
          elseif not req.res then -- no data
            ocall(req.cb, nil, nil)
          else
            ocall(req.cb, nil, req.res[1].data, req.res[1].flags, req.res[1].cas)
          end

          req = nil
        else
          local res, key, flags, len, cas = usplit(line, " ", true)
          if res == "VALUE" then
            req.key   = key
            req.len   = tonumber(len) + #EOL
            req.flags = tonumber(flags) or 0
            req.cas   = tonumber(cas)
          elseif SERVER_ERRORS[res] then
            assert(self._queue.pop() == req)
            ocall(req.cb, Error:new(line))
            req = nil
          else
            self:close()
            return ocall(self.on_error, self, Error:new("Protocol error"))
          end
        end
      end

      if req then -- we need next chunk of data
        assert(req.len)

        local data = self._buff.next_n(data, req.len)
        if not data then return end
        
        if not req.res then req.res = {} end
        req.res[#req.res + 1] = { data = string.sub(data, 1, -3); flags = req.flags; cas = req.cas; key = req.key; }
        req.len = nil
      end

    else
      assert(false, "unknown request type :" .. tostring(req.type))
    end

    data, req = "", self._queue.peek()
  end
end

function Connection:_send(data, type, cb)
  self._cnn:write(data)
  local req
  if type == REQ_RETR_MULTI then
    req = {type = REQ_RETR, cb=cb, multi = true}
  else
    req = {type = type, cb=cb}
  end
  self._queue.push(req)
  return self
end

-- (key, data, [[[exptime,] flags,] noreply])
function Connection:set(...)
  local cb, key, data, exptime, flags, noreply = cb_args(...)
  return self:_send(
    make_store("set", key, data, exptime, flags, noreply),
    REQ_STORE, cb
  )
end

function Connection:get(key, cb)
  return self:_send(
    make_retr("get", key),
    REQ_RETR, cb
  )
end

end
-------------------------------------------------------------------

return {
  Connection = function(...) return Connection:new(...) end
}

