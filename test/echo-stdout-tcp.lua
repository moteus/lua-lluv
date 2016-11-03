local IS_WINDOWS = (package.config:sub(1, 1) == '\\')

local MESSAGE = "HELLO WORLD\n";

if not IS_WINDOWS then

io.stdout:write(MESSAGE)

return

end

-- load to call WSAStartup
local socket = require "socket"
local ffi    = require "ffi"
local ws32   = ffi.load('ws2_32.dll')

ffi.cdef [[
  typedef uint32_t DWORD;
  typedef void     VOID;
  typedef void*    PVOID;
  typedef void*    HANDLE;
  typedef void*    SOCKET;
  typedef uint32_t BOOL;
]]

ffi.cdef[[
  HANDLE __stdcall GetStdHandle(DWORD nStdHandle);
  DWORD __stdcall GetFileType(HANDLE hFile);
  VOID __stdcall Sleep(DWORD dwMilliseconds);
]]

ffi.cdef[[
int send(SOCKET s, const char *buf, int len, int flags);
int WSAGetLastError();
]]

local DWORD  = ffi.typeof('DWORD')
local HANDLE = ffi.typeof('HANDLE')
local SOCKET = ffi.typeof('SOCKET')
local BOOL   = ffi.typeof('BOOL')

local INVALID_HANDLE_VALUE  = ffi.cast(DWORD, -1)
local STD_INPUT_HANDLE      = ffi.cast(DWORD, -10)
local STD_OUTPUT_HANDLE     = ffi.cast(DWORD, -11)
local STD_ERROR_HANDLE      = ffi.cast(DWORD, -12)

local FILE_TYPE_DISK    = 0x0001
local FILE_TYPE_CHAR    = 0x0002
local FILE_TYPE_PIPE    = 0x0003
local FILE_TYPE_REMOTE  = 0x8000
local FILE_TYPE_UNKNOWN = 0x0000

local FILE_TYPES = {
  [FILE_TYPE_DISK   ] = 'FILE_TYPE_DISK';
  [FILE_TYPE_CHAR   ] = 'FILE_TYPE_CHAR';
  [FILE_TYPE_PIPE   ] = 'FILE_TYPE_PIPE';
  [FILE_TYPE_REMOTE ] = 'FILE_TYPE_REMOTE';
  [FILE_TYPE_UNKNOWN] = 'FILE_TYPE_UNKNOWN';
}

local function PrintFileType(h)
  local t = ffi.C.GetFileType(h)
  io.stderr:write(FILE_TYPES[t] or 'FILE_TYPE: ' .. tostring(t), '\n')
end

local stdout = ffi.C.GetStdHandle(STD_OUTPUT_HANDLE)
local stdin  = ffi.C.GetStdHandle(STD_INPUT_HANDLE)

io.stderr:write("STDIN:  ") PrintFileType(stdin)
io.stderr:write("STDOUT: ") PrintFileType(stdout)

local ret = ws32.send(stdout, MESSAGE, #MESSAGE, 0)
if ret ~= #MESSAGE then
  io.stderr:write("SEND ERROR: ", tostring(ret), " / ", tostring(ws32.WSAGetLastError()), "\n")
end

ffi.C.Sleep(100)
