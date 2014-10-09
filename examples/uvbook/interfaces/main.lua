local uv = require "lluv"

local fprintf = function(f, ...) f:write((string.format(...))) end

local stderr, stdout = io.stderr, io.stdout

local info = uv.interface_addresses()

fprintf(stdout, "Number of interfaces: %d\n", #info);

for i, interface in ipairs(info) do
  fprintf(stdout, "Name: %s\n", interface.name);
  fprintf(stdout, "Internal? %s\n", interface.internal and "Yes" or "No");
  fprintf(stdout, "IP address: %s\n", interface.address);
  fprintf(stdout, "\n");
end
