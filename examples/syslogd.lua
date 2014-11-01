local uv = require "lluv"

local month_rfc3164 = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  Jan=true, Feb=true, Mar=true, Apr=true, May=true, Jun=true,
  Jul=true, Aug=true, Sep=true, Oct=true, Nov=true, Dec=true
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

uv.udp()
  :bind("127.0.0.1", "514")
  :start_recv(function(srv, err, data)
    if err then return end
    print(syslog_msg(data))
  end)

uv.run()
