package = "lluv"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lua-lluv/archive/master.zip",
  dir = "lua-lluv-master",
}

description = {
  summary = "Lua binding to libuv",
  detailed = [[
  ]],
  homepage = "https://github.com/moteus/lua-lluv",
  license  = "MIT/X11"
}

dependencies = {
  "lua >= 5.1, < 5.3"
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
  copy_directories = {'doc', 'examples'},

  type = "builtin",

  platforms = {
    windows = { modules = {
      lluv = {
        libraries = {"libuv", "ws2_32"},
      }
    }},
    unix    = { modules = {
      lluv = {
        libraries = {"uv"},
      }
    }}
  },

  modules = {
    lluv = {
      sources = {
        "src/lluv_utils.c", "src/lluv.c",       "src/lluv_error.c",
        "src/lluv_fbuf.c",  "src/lluv_fs.c",    "src/lluv_handle.c",
        "src/lluv_stream.c","src/lluv_idle.c",  "src/lluv_loop.c",
        "src/lluv_tcp.c",   "src/lluv_timer.c", "src/lluv_pipe.c",
        "src/lluv_tty.c",
        "src/l52util.c",
      },
      incdirs   = { "$(UV_INCDIR)" },
      libdirs   = { "$(UV_LIBDIR)" }
    },
  }
}
