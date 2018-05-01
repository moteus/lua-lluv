local uv = require "lluv"

local function net_ifs()
  return function(_, i)
    i = i + 1
    local name = uv.if_indextoname(i)
    if not name then return end
    local iid = uv.if_indextoiid(i)
    return i, name, iid
  end, nil, 0
end

for idx, name, iid in net_ifs() do
  print(idx, name, iid)
end
