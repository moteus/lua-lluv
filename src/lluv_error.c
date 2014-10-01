/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#include "lluv_error.h"
#include <assert.h>

#ifdef _MSC_VER
#  define str_n_len strnlen
#else
#  include <memory.h>

  static size_t str_n_len(const char *start, size_t maxlen){
    const char *end = (const char *)memchr(start, '\0', maxlen);
    return (end) ? (size_t)(end - start) : maxlen;
  }
#endif

#define LLUV_ERROR_NAME LLUV_PREFIX" Error"
static const char *LLUV_ERROR = LLUV_ERROR_NAME;

//{ Error object

LLUV_INTERNAL int lluv_error_create(lua_State *L, int error_category, uv_errno_t error_no, const char *ext){
  static size_t max_ext_len = 4096;
  lluv_error_t *err;
  size_t len;

  if(ext)len = str_n_len(ext, max_ext_len);else len = 0;

  if(0 == len){
    err = lutil_newudatap(L, lluv_error_t, LLUV_ERROR);
  }
  else{
    err = (lluv_error_t*)lutil_newudatap_impl(L, sizeof(lluv_error_t) + len, LLUV_ERROR);
#ifdef _MSC_VER
    strncpy_s(&err->ext[0], len + 1, ext, len);
#else
    strncpy(&err->ext[0], ext, len);
#endif
  }

  err->ext[len] = '\0';
  err->cat      = error_category;
  err->no       = error_no;

  return 1;
}

static lluv_error_t *lluv_check_error(lua_State *L, int i){
  lluv_error_t *err = (lluv_error_t *)lutil_checkudatap (L, i, LLUV_ERROR);
  luaL_argcheck (L, err != NULL, 1, LLUV_ERROR_NAME" expected");
  return err;
}

static int lluv_err_category(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  lua_pushinteger(L, err->cat);
  return 1;
}

static int lluv_err_no(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  lua_pushinteger(L, err->no);
  return 1;
}

static int lluv_err_msg(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  lua_pushstring(L, uv_strerror(err->no));
  return 1;
}

static int lluv_err_name(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  lua_pushstring(L, uv_err_name(err->no));
  return 1;
}

static int lluv_err_ext(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  lua_pushstring(L, err->ext);
  return 1;
}

static int lluv_err_tostring(lua_State *L){
  lluv_error_t *err = lluv_check_error(L,1);
  if(err->ext[0]){
    lua_pushfstring(L, "[%s] %s (%d) - %s",
      uv_err_name(err->no),
      uv_strerror(err->no),
      err->no, err->ext
    );
  }
  else{
    lua_pushfstring(L, "[%s] %s (%d)",
      uv_err_name(err->no),
      uv_strerror(err->no),
      err->no
    );
  }
  return 1;
}

static int lluv_err_equal(lua_State *L){
  lluv_error_t *lhs = lluv_check_error(L, 1);
  lluv_error_t *rhs = lluv_check_error(L, 2);
  lua_pushboolean(L, ((lhs->no == rhs->no)&&(lhs->cat == rhs->cat))?1:0);
  return 1;
}

//}

LLUV_INTERNAL int lluv_fail(lua_State *L, lluv_flags_t flags, int error_category, uv_errno_t error_no, const char *ext){
  if(!(flags & LLUV_FLAG_RAISE_ERROR)){
    lua_pushnil(L);
    lluv_error_create(L, error_category, error_no, ext);
    return 2;
  }

  lluv_error_create(L, error_category, error_no, ext);
  return lua_error(L);
}

static int lluv_error_new(lua_State *L){
  int tp = luaL_checkint(L, 1);
  int no = luaL_checkint(L, 2);
  const char *ext = lua_tostring(L, 3);

  //! @todo checks error type value

  lluv_error_create(L, tp, no, ext);
  return 1;
}

static lluv_uv_const_t lluv_error_constants[] = {

  /* error categories */
  { LLUV_ERR_LIB,        "ERROR_LIB"        },
  { LLUV_ERR_UV,         "ERROR_UV"         },

  /* error codes */
  { UV__EOF,             "EOF"             },
  { UV__UNKNOWN,         "UNKNOWN"         },
  { UV__EAI_ADDRFAMILY,  "EAI_ADDRFAMILY"  },
  { UV__EAI_AGAIN,       "EAI_AGAIN"       },
  { UV__EAI_BADFLAGS,    "EAI_BADFLAGS"    },
  { UV__EAI_CANCELED,    "EAI_CANCELED"    },
  { UV__EAI_FAIL,        "EAI_FAIL"        },
  { UV__EAI_FAMILY,      "EAI_FAMILY"      },
  { UV__EAI_MEMORY,      "EAI_MEMORY"      },
  { UV__EAI_NODATA,      "EAI_NODATA"      },
  { UV__EAI_NONAME,      "EAI_NONAME"      },
  { UV__EAI_OVERFLOW,    "EAI_OVERFLOW"    },
  { UV__EAI_SERVICE,     "EAI_SERVICE"     },
  { UV__EAI_SOCKTYPE,    "EAI_SOCKTYPE"    },
  { UV__EAI_BADHINTS,    "EAI_BADHINTS"    },
  { UV__EAI_PROTOCOL,    "EAI_PROTOCOL"    },
  { UV__E2BIG,           "E2BIG"           },
  { UV__EACCES,          "EACCES"          },
  { UV__EADDRINUSE,      "EADDRINUSE"      },
  { UV__EADDRNOTAVAIL,   "EADDRNOTAVAIL"   },
  { UV__EAFNOSUPPORT,    "EAFNOSUPPORT"    },
  { UV__EAGAIN,          "EAGAIN"          },
  { UV__EALREADY,        "EALREADY"        },
  { UV__EBADF,           "EBADF"           },
  { UV__EBUSY,           "EBUSY"           },
  { UV__ECANCELED,       "ECANCELED"       },
  { UV__ECHARSET,        "ECHARSET"        },
  { UV__ECONNABORTED,    "ECONNABORTED"    },
  { UV__ECONNREFUSED,    "ECONNREFUSED"    },
  { UV__ECONNRESET,      "ECONNRESET"      },
  { UV__EDESTADDRREQ,    "EDESTADDRREQ"    },
  { UV__EEXIST,          "EEXIST"          },
  { UV__EFAULT,          "EFAULT"          },
  { UV__EHOSTUNREACH,    "EHOSTUNREACH"    },
  { UV__EINTR,           "EINTR"           },
  { UV__EINVAL,          "EINVAL"          },
  { UV__EIO,             "EIO"             },
  { UV__EISCONN,         "EISCONN"         },
  { UV__EISDIR,          "EISDIR"          },
  { UV__ELOOP,           "ELOOP"           },
  { UV__EMFILE,          "EMFILE"          },
  { UV__EMSGSIZE,        "EMSGSIZE"        },
  { UV__ENAMETOOLONG,    "ENAMETOOLONG"    },
  { UV__ENETDOWN,        "ENETDOWN"        },
  { UV__ENETUNREACH,     "ENETUNREACH"     },
  { UV__ENFILE,          "ENFILE"          },
  { UV__ENOBUFS,         "ENOBUFS"         },
  { UV__ENODEV,          "ENODEV"          },
  { UV__ENOENT,          "ENOENT"          },
  { UV__ENOMEM,          "ENOMEM"          },
  { UV__ENONET,          "ENONET"          },
  { UV__ENOSPC,          "ENOSPC"          },
  { UV__ENOSYS,          "ENOSYS"          },
  { UV__ENOTCONN,        "ENOTCONN"        },
  { UV__ENOTDIR,         "ENOTDIR"         },
  { UV__ENOTEMPTY,       "ENOTEMPTY"       },
  { UV__ENOTSOCK,        "ENOTSOCK"        },
  { UV__ENOTSUP,         "ENOTSUP"         },
  { UV__EPERM,           "EPERM"           },
  { UV__EPIPE,           "EPIPE"           },
  { UV__EPROTO,          "EPROTO"          },
  { UV__EPROTONOSUPPORT, "EPROTONOSUPPORT" },
  { UV__EPROTOTYPE,      "EPROTOTYPE"      },
  { UV__EROFS,           "EROFS"           },
  { UV__ESHUTDOWN,       "ESHUTDOWN"       },
  { UV__ESPIPE,          "ESPIPE"          },
  { UV__ESRCH,           "ESRCH"           },
  { UV__ETIMEDOUT,       "ETIMEDOUT"       },
  { UV__ETXTBSY,         "ETXTBSY"         },
  { UV__EXDEV,           "EXDEV"           },
  { UV__EFBIG,           "EFBIG"           },
  { UV__ENOPROTOOPT,     "ENOPROTOOPT"     },
  { UV__ERANGE,          "ERANGE"          },
  { UV__ENXIO,           "ENXIO"           },
  { UV__EMLINK,          "EMLINK"          },

  {0, NULL}
};

static const struct luaL_Reg lluv_err_methods[] = {
  { "no",              lluv_err_no               },
  { "msg",             lluv_err_msg              },
  { "name",            lluv_err_name             },
  { "ext",             lluv_err_ext              },
  { "category",        lluv_err_category         },
  { "__tostring",      lluv_err_tostring         },
  { "__eq",            lluv_err_equal            },

  {NULL,NULL}
};

static const struct luaL_Reg lluv_error_functions[] = {
  { "error",     lluv_error_new     },

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_error_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);

  if(!lutil_createmetap(L, LLUV_ERROR, lluv_err_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_error_functions, nup);
  lluv_register_constants(L, lluv_error_constants);
}


