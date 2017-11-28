local uv  = require "lluv"

local write
if pcall(require, "log") then
  write = require "log.writer.list".new(
    require "log.writer.stdout".new(),
    require "log.writer.file".new{
      log_dir        = "./logs", 
      log_name       = 'syslog.log',
      max_size       = 10 * 1024 * 1024,
      roll_count     = 10,
      close_file     = false,
      flush_interval = 1,
      reuse          = true,
    }
  )
else
  write = function(fn, msg)
    print(fn(msg))
  end
end

local month_rfc3164 = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  Jan=1,  Feb=2, Mar=3, Apr=4,  May=5,  Jun=6,
  Jul=7,  Aug=8, Sep=9, Oct=10, Nov=11, Dec=12
}

local header_pat_rfc5424 = 
  "^<(%d+)>%s*"   .. -- PRI
  "(%d+)%s"       .. -- VERSION
  "(%S-)%s+"      .. -- TIMESTAMP
  "(%S-)%s+"      .. -- HOSTNAME
  "(%S-)%s+"      .. -- APP-NAME
  "(%S-)%s+"      .. -- PROCID
  "(%S-)%s+"      .. -- MSGID
""

local SEVERITY = {[0] =
  'EMERGENCY',     -- system is unusable
  'ALERT',         -- action must be taken immediately
  'CRITICAL',      -- critical conditions
  'ERROR',         -- error conditions
  'WARNING',       -- warning conditions
  'NOTICE',        -- normal but significant condition
  'INFO',          -- informational messages
  'DEBUG',         -- debug-level messages
}

local FACILITY = {[0] =
  'kernel',
  'user',
  'mail',
  'system',
  'security',
  'syslog',
  'lpd',
  'nntp',
  'uucp',
  'time',
  'security',
  'ftpd',
  'ntpd',
  'logaudit',
  'logalert',
  'clock',
  'local0',
  'local1',
  'local2',
  'local3',
  'local4',
  'local5',
  'local6',
  'local7',
}

local function build_matrix()
  local t = {}
  for i = 0, #SEVERITY do
    for j = 0, #FACILITY do
      local pri = j * 8 + i
      t[pri] = {i, j}
    end
  end
  return t
end

local MATRIX = build_matrix()

-- via math
local function pri_decode_calc(pri, as_string)
  pri = tonumber(pri)
  local facility = math.floor(pri / 8)
  local severity = pri - facility * 8
  if as_string then
    return SEVERITY[severity] or tostring(severity), FACILITY[facility] or tostring(facility)
  end
  return severity, facility
end

-- via matrix
local function pri_decode(pri, as_string)
  local t = MATRIX[tonumber(pri)]
  if t then
    local severity, facility = t[1], t[2]
    if as_string then
      return SEVERITY[severity] or tostring(severity), FACILITY[facility] or tostring(facility)
    end
    return severity, facility
  end
  return pri_decode_calc(pri, as_string)
end

local function syslog_msg_rfc3164(msg)
  local b, e, pri = msg:find("^<(%d+)>%s*")
  if not pri then return end

  msg = msg:sub(e+1)
  local b, e, mon, day, time = msg:find("^(...)%s(..)%s(..:..:..)%s+")
  if b and month_rfc3164[mon] then
    msg = msg:sub(e+1)
  else -- invalid date or no date so we MUST set it byself
    local now = os.date("*t")
    mon  = month_rfc3164[now.month]
    day  = now.day < 10 and (" " .. now.day) or tostring(now.day)
    time = string.format("%.2d:%.2d:%.2d", now.hour, now.min, now.sec)
  end

  local host, msg = msg:match("^(%S+)%s+(.*)$")

  return "rfc3164", pri, mon, day, time, host, msg
end

-- rfc5424 or rfc3164
local function syslog_msg(msg)
  local _, hend, pri, ver, ts, host, app, procid, msgid = msg:find(header_pat_rfc5424)

  if not pri then return syslog_msg_rfc3164(msg) end

  msg = msg:sub(hend+1)
  local sdata
  if msg:sub(1, 1) == "-" then
    sdata = "-"
    msg = msg:sub(3)
  else
    if msg:sub(1,1) ~= "[" then return end

    local b, e, elem
    sdata = {}
    while true do
      b, e, elem = msg:find("(%b[])", e)

      if not elem then return end

      sdata[#sdata + 1] = elem:sub(2,-2)
      e = e + 1

      if msg:sub(e, e) ~= '[' then break end
    end
    msg = msg:sub(e + 1)
  end

  return "rfc5424", pri, ver, ts, host, app, procid, msgid, sdata, msg
end

local date_fmt = {
  rfc3164 = function(m, d, t)
    return string.format("%s-%.2d-%.2d %s",
      os.date("%Y"), month_rfc3164[m], tonumber(d), t
    )
  end;
  rfc5424 = function(ts)
    return ts
  end;
}

local function trim(s)
  return (string.match(s, "^[%s%z]*(.-)[%s%z]*$"))
end

local writers = {
  rfc3164 = function(source_ip, source_port, rfc, ...)
    local  pri, mon, day, time, host, msg = ...
    local d = date_fmt.rfc3164(mon, day, time)
    local severity, facility = pri_decode(pri, true)
    return write(trim, string.format("[%s] %s %s:[%s] %s %s", source_ip, d, severity, facility, host, msg))
  end;

  rfc5424 = function(source_ip, source_port, rfc, ...)
    local pri, ver, ts, host, app, procid, msgid, sdata, msg = ...
    local d = date_fmt.rfc5424(ts)
    local severity, facility = pri_decode(pri, true)
    return write(trim, string.format("[%s] %s %s:[%s] %s[%s] %s", source_ip, d, severity, facility, host, app, msg))
  end;
}

local function write_log(source_ip, source_port, rfc, ...)
  local writer = rfc and writers[rfc]
  if rfc then writer(source_ip, source_port, rfc, ...) end
end

uv.udp()
  :bind("*", "514")
  :start_recv(function(srv, err, data, flags, host, port)
    if err then return end
    write_log(host, port, syslog_msg(data))
  end)

uv.run()
