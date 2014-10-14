-- Implementation of https://github.com/silentbicycle/lua-memcached 
-- using lua-lluv library
--
--[[

local umc = mc.new()

umc:connect("127.0.0.1", function(self, err)
  if err then return print(err) end
  self:set("test_key", "test_value", 10, function(...)
    print(...)
    self:get("test_key", function(...)
      print(...)
      self:delete("test_key", function(...)
        print(...)
        self:quit(function(...)
          print(...)
          self:close()
        end)
      end)
    end)
  end)
end)

uv.run(debug.traceback)

--]]

local uv = require "lluv"
local va = require "vararg"

local function Next(eol)
  local eol  = eol or "\r\n"
  local neol = #eol

  local tail = ""

  local function next_line(data)
    data = tail .. data

    local e, e2 = string.find(data, eol, nil, true)
    if e then
      local line = string.sub(data, 1, e - 1)
      tail = string.sub(data, e2 + 1)
      return line
    else
      tail = data
    end
    return nil
  end

  local function next_n(data, n)
    data = tail .. data
    if n > #data then
      tail = data
      return nil
    end

    local res = string.sub(data, 1, n)
    tail = string.sub(data, n+1)
    return res
  end

  local function reset()
    tail = ""
  end

  local function self_test()
      -- test next_xxx
    assert("aaa" == next_line("aaa" .. eol .. "bbb"))
    assert("bbb" == tail, tail)

    assert("bbbccc" == next_line("ccc" .. eol .. "ddd" .. eol))
    assert("ddd"..eol == tail, tail)

    assert("ddd" == next_line(eol))
    assert(eol == tail, "'" .. tail .."'")

    assert("" == next_line(""))
    assert("" == tail, "'" .. tail .."'")

    assert(nil == next_line("aaa"))
    assert("aaa" == tail, "'" .. tail .."'")

    assert("aaa" == next_n("123456", 3))
    assert("123456" == tail, "'" .. tail .."'")

    assert(nil == next_n("", 8))
    assert("123456" == tail, "'" .. tail .."'")

    assert("123"== next_n("", 3))
    assert("456" == tail, "'" .. tail .."'")

    assert("456" == next_line(eol))
    assert("" == tail, "'" .. tail .."'")

    tail = ""
  end

  local function append(data)
    tail = tail .. data
  end

  return {
    line   = next_line;
    n      = next_n;
    reset  = reset;
    append = append;
  }
end

local EOL = "\r\n"

local fmt = string.format

local function cb_args(...)
  local n = select("#", ...)
  local cb = va.range(n, n, ...)
  assert(type(cb) == 'function')
  return cb, va.remove(n, ...)
end

local function get_key(self, key)
  if self.on_key then return self:on_key(key) end
  return key
end

local function store_cmd(...)
  local fn, self, cmd, key, data, exptime, flags, noreply, cas_id = cb_args(...)

  key = get_key(self, key)

  if type(data) == "number" then data = tostring(data) end
  if not key then return false, "no key"
  elseif type(data) ~= "string" then return false, "no data" end
  exptime = exptime or 0
  noreply = noreply or false
  flags   = flags   or 0

  local buf = {cmd, key, flags, exptime, #data, cas_id}
  if noreply then buf[#buf+1] = "noreply" end

  buf = table.concat(buf, " ") .. EOL ..  data .. EOL

  if noreply then return self:send(buf, fn) end
  return self:send_recv(buf, fn)
end

local function do_get(...)
  local fn, self, cmd, keys, pattern = cb_args(...)

  local mk = {} -- map key
  local rk      -- real keys
  if type(keys) == "string" then 
    keys = { get_key(self, keys) }
  else
    rk = {}
    for i, key in ipairs(keys) do
      rk[i]       = get_key(self, key)
      mk[ rk[i] ] = key
    end
  end

  local buf = fmt("%s %s\r\n", cmd, table.concat(rk or keys, " "))

  return self:send(buf, function(self, err)
    if err then return fn(self, err) end

    local res, key, flags, len, data, cas = {}
    local on_line, on_data

    function on_line(self, err, line)
      if err then return fn(self, err) end
      if line ~= "END" then
        key, flags, len, cas = line:match(pattern)
        if not key then
          self:close()
          return fn(self, 'bad response:' .. line)
        end
        return self:recv_n(tonumber(len) + 2, on_data)
      end

      if not rk then return fn(self, nil, data, flags, cas) end
      return fn(self, nil, res)
    end

    function on_data(self, err, line)
      if err then return fn(self, err) end
      data = line:sub(1, -3)
      res[ mk[key] or key ] = { data=data, flags=flags, cas = cas }
      return self:recv_line(on_line)
    end

    self:recv_line(on_line)
  end)
end

local function adjust_key(self, cmd, key, val, noreply, fn)
  key = get_key(self, key)
  assert(val, "No number")
  noreply = noreply and " noreply" or ""
  local msg = fmt("%s %s %d%s\r\n", cmd, key, val, noreply)

  if noreply ~= "" then return self:send(msg, fn) end

  return self:send_recv(msg, fn)
end

--------------------------------------------------
local umc = {} do
umc.__index = umc

function umc:new()
  local o  = setmetatable({}, self)

  return o
end

function umc:connect(...)
  assert(not self:connected())

  local fn, host, port = cb_args(...)

  self._cli = uv.tcp()
  self._cli.data = self

  host = host or "127.0.0.1"
  port = port or "11211"

  self._cli:connect(host, port, function(cli, err)
    local self = cli.data
    if err then
      cli.data:close()
      return fn(cli.data, err)
    end

    self._next = Next("\r\n")
  
    cli:start_read(function(cli, err, data)
      local self = cli.data
      if err then
        cli.data:close()
        if self._on_data then
          return self:_on_data(err)
        else
          self._recv_error = err
        end
        return 
      end

      if self._on_data then
        return self:_on_data(nil, data)
      end

      self._next.append(data)
    end)

    fn(cli.data)
  end)
end

do -- private

function umc:send(msg, fn)
  self._cli:write(msg, function(cli, err)
    if err then cli.data:close() end
    fn(cli.data, err)
  end)
end

function umc:recv_line(fn)
  local data = self._next.line("")
  if data then return fn(self, nil, data) end

  self._on_data = function(self, err, data)
    if err then
      self._on_data = nil
      return fn(self, err)
    end

    local line = self._next.line(data)
    if line then
      self._on_data = nil
      return fn(self, nil, line)
    end
  end
end

function umc:recv_n(n, fn)
  local data = self._next.n("", n)
  if data then return fn(self, nil, data) end
  self._on_data = function(self, err, data)
    if err then
      self._on_data = nil
      return fn(self, err)
    end

    local line = self._next.n(data, n)
    if line then
      self._on_data = nil
      return fn(self, nil, line)
    end
  end
end

function umc:send_recv(msg, fn)
  self:send(msg, function(self, err)
    if err then return fn(self, err) end
    self:recv_line(function(self, err, data)
      fn(self, err, data)
    end, true)
  end)
end

end

do -- get

function umc:get(keys, fn)
  assert(not self:busy())
  return do_get(self, "get", keys, "^VALUE ([^ ]+) (%d+) (%d+)", fn)
end

function umc:gets(keys, fn)
  assert(not self:busy())
  return do_get(self, "gets", keys, "^VALUE ([^ ]+) (%d+) (%d+) (%d+)", fn)
end

end

do -- set

---Set a key to a value.
-- @tparam string key A key, which cannot have whitespace or control characters
--     and must be less than 250 chars long.
-- @tparam string data Value to associate with the key. Must be under 1 megabyte.
-- @tparam[opt] number exptime Optional expiration time, in seconds.
-- @tparam[opt] number flags Optional 16-bit int to associate with the key,
--     for bit flags.
-- @tparam[opt] boolean noreply Do not expect a reply, just set it.
-- @tparam function callback callback function that will be called
function umc:set(...)
  assert(not self:busy())
  return store_cmd(self, "set", ...)
end

function umc:add(...)
  assert(not self:busy())
  return store_cmd(self, "add", ...)
end

function umc:replace(...)
  assert(not self:busy())
  return store_cmd(self, "replace", ...)
end

function umc:append(...)
  assert(not self:busy())
  return store_cmd(self, "append", ...)
end

function umc:prepend(...)
  assert(not self:busy())
  return store_cmd(self, "prepend", ...)
end

function umc:cas(...)
  assert(not self:busy())
  return store_cmd(self, "cas", ...)
end

function umc:connected()
  return not not self._cli
end

function umc:busy()
  --- @fixme
  return not not self._on_data
end

function umc:close()
  if self._cli then
    self._cli:close()
    self._cli = nil
  end
end

end

do -- misc

function umc:version(fn)
  assert(not self:busy())
  return self:send_recv("version\r\n", fn)
end

function umc:delete(...)
  assert(not self:busy())
  local fn, key, noreply = cb_args(...)
  
  key = get_key(self, key)
  local msg = fmt("delete %s%s\r\n", key, noreply and " noreply" or "")
  if noreply then return self:send(msg, fn) end
  return self:send_recv(msg, fn)
end

function umc:flush_all(fn)
  assert(not self:busy())
  return self:send_recv("flush_all\r\n", fn)
end

function umc:incr(...)
  assert(not self:busy())
  local fn, key, val, noreply = cb_args(...)
  return adjust_key(self, "incr", key, val, noreply, fn)
end

function umc:decr(...)
  assert(not self:busy())
  local fn, key, val, noreply = cb_args(...)
  return adjust_key(self, "decr", key, val, noreply, fn)
end

function umc:stats(...)
  local fn, key = cb_args(...)
  key = key or ''
  if (key ~= '') and (not STATS_KEYS[key]) then
    return error(fmt("Unknown stats key '%s'", key))
  end

  return self:send("stats " ..key .. "\r\n", function(self, err)
    if err then return fn(self, err) end

    local s = {}
    local function on_line(self, err, line)
      if err then return fn(self, err) end
      if line ~= "END" then
        if line == 'ERROR' then return fn(self, line) end
        local k,v = line:match("STAT ([^ ]+) (.*)")
        if k ~= "version" then v = tonumber(v) end
        s[k] = v
        return self:recv_line(on_line)
      end
      return fn(self, nil, s)
    end

    return self:recv_line(on_line)
  end)
end

function umc:quit(fn)
  return self:send_recv("quit\r\n", fn)
end

end

end
--------------------------------------------------

return {
  new = function(...) return umc:new() end
}
