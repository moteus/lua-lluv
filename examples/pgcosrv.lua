-- Basic PostgreSQL Server based on Lua coroutine
--
-- Based on http://stackoverflow.com/a/13685364/2328287
--
-- -- Test client
-- local odbc = require "odbc.dba"
--
-- env = odbc.Environment()
--
-- cnn = env:connect{
--   driver   = "{PostgreSQL ODBC Driver(ANSI)}";
--   Server   = "127.0.0.1";
--   Port     = 9876;
--   Database = "mydb";
--   Uid      = "postgres";
--   Pwd      = "123456";
-- }
--
-- cnn:each("select * from test", print)
--

local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"
local try    = require "try"
local struct = require "struct"

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

----------------------------------------------------------------------------
-- Implement PostgreSQL Server
local PgSrv = ut.class() do

PgSrv.TYPES = {
  int2 = { id = 21; len =  2; binary = false};
  int4 = { id = 23; len =  4; binary = false};
  int8 = { id = 20; len =  8; binary = false};
  text = { id = 25; len = -1; binary = false};
}

function PgSrv:__init(cli)
  self._cli = assert(cli)
  return self
end

function PgSrv:send(data)
  return self._cli:send(data)
end

function PgSrv:recv(n)
  return self._cli:receive(n)
end

function PgSrv:recv_greet()
  local data, err = self:recv(8)
  if not data then return nil, err end
  local len, ver = struct.unpack(">i4i4", data)

  assert(len >= 8, len)
  data, err = self:recv(len - 8)
  if not data then return nil, err end
  local t = ut.split(data, "\0", true)
  local res = {}
  local i = 1 while i < #t do
    res[t[i]] = t[i + 1]
    i = i + 2
  end
  return ver, res
end

function PgSrv:recv_msg()
  local data, err = self:recv(5)
  if not data then return nil, err end
  local typ, len = struct.unpack(">c1i4", data)

  assert(len >= 4, len)
  data, err = self:recv(len - 4)
  if not data then return nil, err end
  return typ, data
end

function PgSrv:send_msg(typ, data)
  local header = struct.pack(">c1i4", typ, #data + 4)
  return self._cli:send{header, data}
end

function PgSrv:send_auth_request()
  return self:send_msg('R', struct.pack(">i4", 3))
end

function PgSrv:recv_auth_response()
  local typ, data = self:recv_msg()
  if not typ then return nil, data end
  assert(typ == 'p', typ)
  return (ut.split_first(data, "\0", true))
end

function PgSrv:send_auth_ok()
  return self:send_msg('R', struct.pack("i4", 0))
end

function PgSrv:send_ready_for_query()
  return self:send_msg('Z', 'I')
end

function PgSrv:recv_query()
  local typ, data = self:recv_msg()
  if not typ then return nil, data end
  assert(typ == 'Q', typ)
  return (ut.split_first(data, "\0", true))
end

local function FieldName(name, type, size)
  local tableid      = 0
  local columnid     = 0

  local datatypeid   = type.id
  local datatypesize = (type.len == -1) and size or type.len
  local typemodifier = -1
  local format_code  = type.binary and 1 or 0 -- 0=text 1=binary

  return name .. "\000" .. struct.pack(">i4i2i4i2i4i2", 
    tableid, columnid, datatypeid, 
    datatypesize, typemodifier, format_code
  )
end

function PgSrv:send_query_result(Header, Data)
  if Header then
    local fields = {}
    for _, name in ipairs(Header) do
      fields[#fields+1] = FieldName( (unpack or table.unpack)(name) )
    end

    local ok, err = self:send_msg('T', struct.pack(">i2c0", #Header, table.concat(fields)))
    if not ok then return nil, err end

    for _, row in ipairs(Data) do
      local cols = {}
      for _, v in ipairs(row) do
        v = tostring(v)
        cols[#cols + 1] = struct.pack(">i4", #v) .. v
      end

      ok, err = self:send_msg('D', struct.pack(">i2c0", #Header, table.concat(cols)))
      if not ok then return nil, err end
    end
  end
  return self:send_query_complite(Data and #Data or 0)
end

function PgSrv:send_error(err)
--[[
S 
Severity: the field contents are ERROR, FATAL, or PANIC (in an error message), or WARNING, NOTICE, DEBUG, INFO, or LOG (in a notice message), or a localized translation of one of these. Always present.

C
Code: the SQLSTATE code for the error (see Appendix A). Not localizable. Always present.

M
Message: the primary human-readable error message. This should be accurate but terse (typically one line). Always present.

D
Detail: an optional secondary error message carrying more detail about the problem. Might run to multiple lines.

H
Hint: an optional suggestion what to do about the problem. This is intended to differ from Detail in that it offers advice (potentially inappropriate) rather than hard facts. Might run to multiple lines.

P
Position: the field value is a decimal ASCII integer, indicating an error cursor position as an index into the original query string. The first character has index 1, and positions are measured in characters not bytes.

p
Internal position: this is defined the same as the P field, but it is used when the cursor position refers to an internally generated command rather than the one submitted by the client. The q field will always appear when this field appears.

q
Internal query: the text of a failed internally-generated command. This could be, for example, a SQL query issued by a PL/pgSQL function.

W
Where: an indication of the context in which the error occurred. Presently this includes a call stack traceback of active procedural language functions and internally-generated queries. The trace is one entry per line, most recent first.

F
File: the file name of the source-code location where the error was reported.

L
Line: the line number of the source-code location where the error was reported.

R
Routine: the name of the source-code routine reporting the error.
]]

  local res, size = {}, 0
  for t, v in pairs(err) do
    res[#res + 1] = t .. v .. '\0'
    size = size + #res[#res]
  end
  res[#res + 1] = '\0'
  size = size + 1

  return self:send_msg('E', table.concat(res))
end

function PgSrv:send_query_complite(n)
  return self:send_msg("C", "SELECT " .. tostring(n) .. "\0")
end

function PgSrv:close()
  self._cli:close()
  return true
end

end
----------------------------------------------------------------------------

----------------------------------------------------------------------------
local PgSrvInstance do

local PgSrvInstance_ = try.protect(function(pg, session)

  local check = try.new(function() pg:close() end)

  local ver, data = check(pg:recv_greet())
  if ver == 80877103 then -- SSL?
    print("SSL Request")
    pg:send("N")
    ver, data = check(pg:recv_greet())
  end

  local ok, err = session:greet(ver, data)
  if not ok then
    if ok == false then pg:send_error(err) end
    return check(ok, err)
  end

  check(pg:send_auth_request())

  local pass = check(pg:recv_auth_response())

  ok, err = session:auth(pass)
  if not ok then
    if ok == false then pg:send_error(err) end
    return check(ok, err)
  end

  check(pg:send_auth_ok())

  -- test query
  while true do
    check(pg:send_ready_for_query())

    local qry = check(pg:recv_query())

    local status, header, data = session:query(qry)
    if status == nil then return check(nil, "closed") end
    if status == false then
      ok, err = pg:send_error(header)
    else
      ok, err = pg:send_query_result(header, data)
    end
    check(ok, err)
  end
end)

PgSrvInstance = function(usok, cb)
  local cli = socket.tcp(usok)
  local pg  = PgSrv.new(cli)

  local session = cb(true)
  if not session then
    pg:close()
    return
  end

  local ok, err = PgSrvInstance_(pg, session)
  if err then
    if (type(err) == "table") and err.M then err = err.M end
    session:error(err)
  end
end

end
----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- Implement PostgreSQL Session
local PgStaticSession = ut.class() do

function PgStaticSession:__init(pwd, qry)
  self._pwd = assert(pwd)

  local t = {}
  for k, v in pairs(qry) do
    t[k], t[k..';'] = v, v
  end
  self._qry = t

  return self
end

function PgStaticSession:greet(version, greet)
  self._version = version
  self._greet   = greet
  print("Greet:", math.floor(version/2^16) .. "." .. math.mod(version,2^16))
  for k,v in pairs(greet) do print("", k, "=>", v) end
  return self
end

function PgStaticSession:auth(pwd)
  if pwd ~= self._pwd then
    print("Auth fail")

    return false, {
      S = 'ERROR';
      C = '28P01';
      M = 'Invalid user name or password';
    }
  end
  print("Auth:", self._greet.user, "/", pwd)
  return self
end

function PgStaticSession:query(qry)
  print("Query:", qry)
  local result = self._qry[qry] or self._qry["*"]
  if result then
    return true, result.header, result
  end
  return false, {
    S = 'ERROR';
    C = '42601';
    M = 'Syntax error';
  }
end

function PgStaticSession:error(err)
  print("ERROR:", err)
end

end
----------------------------------------------------------------------------

local function main(host, port)
  local StaticResult = {
    ["select oid, typbasetype from pg_type where typname = 'lo'"] = {};
    ["select pg_client_encoding()"] = {
      header = {
        {"pg_client_encoding", PgSrv.TYPES.text, 20};
      };
      {"WIN1251"};
    };
    ["*"] = {
      header = {
        {'Field1', PgSrv.TYPES.int4}, {'Field2', PgSrv.TYPES.int4}, {'Field3', PgSrv.TYPES.text, 20}
      };
      {1, 2, "Hello"    },
      {3, 4, ", "       },
      {5, 6, "world !!!"},
    };
  }

  local function server(ok, err)
    if not ok then return print("Error:", err) end
    return PgStaticSession.new("123456", StaticResult)
  end

  CreateServer(host, port, function(cli, err)
    if not cli then return server(nil, err) end
    ut.corun(PgSrvInstance, cli, server)
  end)

  uv.run(debug.traceback)
end

main("127.0.0.1", 9876)
