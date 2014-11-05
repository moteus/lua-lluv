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

local uv = require "lluv"
local ut = require "lluv.utils"

----------------------------------------------------------------------------
local CoSock = ut.class() do

function CoSock:__init(buffer)
  self._buf = assert(buffer)
  return self
end

function CoSock:recv_line(eol)
  while true do
    local msg = self._buf:next_line(nil, eol)
    if msg then return msg end
    local ok, err = coroutine.yield()
    if not ok then return nil, err end
  end
end

function CoSock:recv_n(n)
  while true do
    local msg =self._buf:next_n(nil, n)
    if msg then return msg end
    local ok, err = coroutine.yield()
    if not ok then return nil, err end
  end
end

function CoSock:send(data)
  return coroutine.yield(data)
end

end
----------------------------------------------------------------------------

----------------------------------------------------------------------------
local function CreateServer(ip, port, cb)
  local function on_connect(srv, err)
    if err then return cb(nil, err) end
    return cb(srv:accept())
  end
  uv.tcp()
    :bind(ip, port)
    :listen(on_connect)
end
----------------------------------------------------------------------------

----------------------------------------------------------------------------
local function CreateCoServer(ip, port, cb, cb_err)
  CreateServer(ip, port, function(cli, err)

    local server = coroutine.create(function(buffer, err)
      local cli
      if buffer then cli = CoSock.new(buffer) end
      return cb(cli, err)
    end)

    local on_resume_data, server_resume

    if cb_err then
      server_resume = function(...)
        local ok, data = coroutine.resume(server, ...)
        if not ok then
          cb_err(data)
        elseif data then
          on_resume_data(data)
        end
        return ok, data
      end
    else
      server_resume = function(...)
        local ok, data = coroutine.resume(server, ...)
        if ok and data then on_resume_data(data) end
        return ok, data
      end
    end

    on_resume_data = function(data)
      cli:write(data, function(cli, err)
        server_resume(not err, err)
      end)
    end

    if err then return server_resume(nil, err) end

    local buffer = ut.Buffer.new("\r\n")

    local ok, cerr = server_resume(buffer)
    if not ok then return cli:close() end

    cli:start_read(function(cli, err, data)
      if data then buffer:append(data) end

      if err then
        cli:close()
        return server_resume(nil, err)
      end

      if not server_resume(true) then return cli:close() end

    end)
  end)
end
----------------------------------------------------------------------------

--------------------------------------
-- Implement PostgreSQL Session
--------------------------------------
local struct = require "struct"

----------------------------------------------------------------------------
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
  return self._cli:recv_n(n)
end

function PgSrv:recv_greet()
  local data, err = self:recv(8)
  if not data then return nil, err end
  local len, ver = struct.unpack(">i4i4", data)

  assert(len >= 8, len)
  data, err = self:recv(len - 8)
  if not data then return nil, err end
  return ver, data
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
  return data
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
  return data
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

function PgSrv:send_query_result(Data)
  if Data and Data.header then
    local fields = {}
    for _, name in ipairs(Data.header) do
      fields[#fields+1] = FieldName( (unpack or table.unpack)(name) )
    end

    local ok, err = self:send_msg('T', struct.pack(">i2c0", #Data.header, table.concat(fields)))
    if not ok then return nil, err end

    for _, row in ipairs(Data) do
      local cols = {}
      for _, v in ipairs(row) do
        v = tostring(v)
        cols[#cols + 1] = struct.pack(">i4", #v) .. v
      end

      ok, err = self:send_msg('D', struct.pack(">i2c0", #Data.header, table.concat(cols)))
      if not ok then return nil, err end
    end
  end
  return self:send_query_complite(Data and #Data or 0)
end

function PgSrv:send_query_complite(n)
  return self:send_msg("C", "SELECT " .. tostring(n) .. "\0")
end

end
----------------------------------------------------------------------------

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

CreateCoServer("127.0.0.1", 9876, function(cli)
  local pg = PgSrv.new(cli)

  local ver, data = assert(pg:recv_greet())
  if ver == 80877103 then -- SSL?
    assert(data == "")
    print("SSL Request")
    pg:send("N")
    ver, data = assert(pg:recv_greet())
  end

  print("GREET", ver, ut.usplit(data, "\0", true))

  print("**************************")
  print("AUTH REQ", pg:send_auth_request() )
  print("AUTH RES", pg:recv_auth_response())
  print("AUTH OK ", pg:send_auth_ok())
  print("**************************")

  -- test query
  while true do
    print("READY  ", pg:send_ready_for_query())
    local qry, err = pg:recv_query()
    print("QUERY  ", qry, err)
    local result = StaticResult[qry] or  StaticResult["*"]
    print("RESULT ", pg:send_query_result(result))
    print("**************************")
  end

  print("server done")
end, print)

uv.run(debug.traceback)
