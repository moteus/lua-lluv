package = "lluv"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lua-lluv/archive/master.zip",
  dir = "lua-lluv-master",
}

description = {
  summary    = "Lua low-level binding to libuv",
  homepage   = "https://github.com/moteus/lua-lluv",
  license    = "MIT/X11",
  maintainer = "Alexey Melnichuk",
  detailed   = [[
  ]],
}

dependencies = {
  "lua >= 5.1, < 5.4"
}

external_dependencies = {
  platforms = {
    windows = {
      UV = {
        header  = "uv.h",
        library = "libuv",
      }
    };
    unix = {
      UV = {
        header  = "uv.h",
        library = "uv",
      }
    };
  }
}

build = {
  copy_directories = {'doc', 'examples', 'test'},

  type = "builtin",

  platforms = {
    windows = { modules = {
      lluv = {
        libraries = {"libuv", "ws2_32", "Iphlpapi", "Psapi", "Advapi32"},
      }
    }},
    linux   = { modules = {
      lluv = {
        libraries = {"uv", "rt"},
      }
    }},
    unix    = { modules = {
      lluv = {
        libraries = {"uv"},
      }
    }},
  },

  modules = {
    lluv = {
      sources = {
        "src/lluv_utils.c",    "src/lluv.c",          "src/lluv_error.c",
        "src/lluv_fbuf.c",     "src/lluv_fs.c",       "src/lluv_handle.c",
        "src/lluv_stream.c",   "src/lluv_idle.c",     "src/lluv_loop.c",
        "src/lluv_tcp.c",      "src/lluv_timer.c",    "src/lluv_pipe.c",
        "src/lluv_tty.c",      "src/lluv_udp.c",      "src/lluv_prepare.c",
        "src/lluv_check.c",    "src/lluv_poll.c",     "src/lluv_signal.c",
        "src/lluv_fs_event.c", "src/lluv_fs_poll.c",  "src/lluv_req.c",
        "src/lluv_misc.c",     "src/lluv_process.c",  "src/lluv_dns.c",
        "src/l52util.c",       "src/lluv_list.c"
      },
      incdirs   = { "$(UV_INCDIR)" },
      libdirs   = { "$(UV_LIBDIR)" }
    },
    ["lluv.utils"    ] = "src/lua/lluv/utils.lua",
    ["lluv.luasocket"] = "src/lua/lluv/luasocket.lua",
  }
}
