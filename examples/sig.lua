local uv = require "lluv"

uv.signal():start(uv.SIGINT,   function(...) print("SIGINT   : ", ...) end)
uv.signal():start(uv.SIGBREAK, function(...) print("SIGBREAK : ", ...) end)
uv.signal():start(uv.SIGHUP,   function(...) print("SIGHUP   : ", ...) end)
uv.signal():start(uv.SIGWINCH, function(...) print("SIGWINCH : ", ...) end)

uv.run()
