/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#include "lluv.h"
#include "lluv_dns.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include "lluv_req.h"
#include <memory.h>
#include <assert.h>

static void lluv_on_getnameinfo(uv_getnameinfo_t* arg, int status, const char* hostname, const char* service){
  lluv_req_t  *req  = lluv_req_byptr((uv_req_t*)arg);
  lluv_loop_t *loop = lluv_loop_byptr(arg->loop);
  lua_State   *L    = loop->L;

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  if(!IS_(loop, OPEN)){
    lluv_req_free(L, req);
    return;
  }

  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);
  lluv_req_free(L, req);
  assert(!lua_isnil(L, -1));

  lluv_loop_pushself(L, loop);
  lluv_push_status(L, status);
  if(hostname)lua_pushstring(L, hostname); else lua_pushnil(L);
  if(service) lua_pushstring(L, service);  else lua_pushnil(L);

  lluv_lua_call(L, 4, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static void lluv_on_getaddrinfo(uv_getaddrinfo_t* arg, int status, struct addrinfo* res){
  lluv_req_t  *req   = lluv_req_byptr((uv_req_t*)arg);
  lluv_loop_t *loop  = lluv_loop_byptr(arg->loop);
  lua_State   *L     = loop->L;
  struct addrinfo* a = res;
  int i = 0;

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);
  lluv_req_free(L, req);
  assert(!lua_isnil(L, -1));

  lluv_loop_pushself(L, loop);

  if(status < 0){
    uv_freeaddrinfo(res);
    lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);
    lluv_lua_call(L, 2, 0);
    LLUV_CHECK_LOOP_CB_INVARIANT(L);
    return;
  }

  lua_pushnil(L);
  lua_newtable(L);
  for(a = res; a; a = a->ai_next){
    char buf[INET6_ADDRSTRLEN + 1];
    int port;
    lua_newtable(L);

    switch (a->ai_family){
      case AF_INET:{
        struct sockaddr_in *sa = (struct sockaddr_in*)a->ai_addr;
        uv_ip4_name(sa, buf, sizeof(buf));
        lua_pushstring(L, buf);
        lua_setfield(L, -2, "address");
        if((port = ntohs(sa->sin_port))){
          lua_pushinteger(L, port);
          lua_setfield(L, -2, "port");
        }
        break;
      }

      case AF_INET6:{
        struct sockaddr_in6 *sa = (struct sockaddr_in6*)a->ai_addr;
        uv_ip6_name(sa, buf, sizeof(buf));
        lua_pushstring(L, buf);
        lua_setfield(L, -2, "address");
        if((port = ntohs(sa->sin6_port))){
          lua_pushinteger(L, port);
          lua_setfield(L, -2, "port");
        }
        break;
      }
    }

    if(a->ai_canonname){
      lua_pushstring(L, a->ai_canonname);
      lua_setfield(L, -2, "canonname");
    }

    lua_rawseti(L, -2, ++i);
  }

  uv_freeaddrinfo(res);
  lluv_lua_call(L, 3, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static int lluv_getaddrinfo(lua_State *L){
  static const lluv_uv_const_t ai_family[] = {
    { AF_UNSPEC,       "unspec"    },
    { AF_INET,         "inet"      },
    { AF_INET6,        "inet6"     },
    { AF_UNIX,         "unix"      },

    // { AF_IMPLINK,      "implink"   },
    // { AF_PUP,          "pup"       },
    // { AF_CHAOS,        "chaos"     },
    // { AF_NS,           "ns"        },
    // { AF_IPX,          "ipx"       },
    // { AF_ISO,          "iso"       },
    // { AF_OSI,          "osi"       },
    // { AF_ECMA,         "ecma"      },
    // { AF_DATAKIT,      "datakit"   },
    // { AF_CCITT,        "ccitt"     },
    // { AF_SNA,          "sna"       },
    // { AF_DECnet,       "decnet"    },
    // { AF_DLI,          "dli"       },
    // { AF_LAT,          "lat"       },
    // { AF_HYLINK,       "hylink"    },
    // { AF_APPLETALK,    "appletalk" },
    // { AF_NETBIOS,      "netbios"   },
    // { AF_VOICEVIEW,    "voiceview" },
    // { AF_FIREFOX,      "firefox"   },
    // { AF_UNKNOWN1,     "unknown1"  },
    // { AF_BAN,          "ban"       },
    // { AF_ATM,          "atm"       },
    // { AF_CLUSTER,      "cluster"   },
    // { AF_12844,        "12844"     },
    // { AF_IRDA,         "irda"      },
    // { AF_NETDES,       "netdes"    },

    //! @todo extend list

    { 0, NULL }
  };

  static const lluv_uv_const_t ai_stype[] = {
    { SOCK_STREAM,        "stream"    },
    { SOCK_DGRAM,         "dgram"     },
    { SOCK_RAW,           "raw"       },
    // { SOCK_RDM,           "rdm"       },
    // { SOCK_SEQPACKET,     "seqpacket" },

    //! @todo extend list

    { 0, NULL }
  };

  static const lluv_uv_const_t ai_proto[] = {
    { IPPROTO_TCP,  "tcp"  },
    { IPPROTO_UDP,  "udp"  },
    { IPPROTO_ICMP, "icmp" },

    //! @todo extend list

    { 0, NULL }
  };

  static const lluv_uv_const_t FLAGS[] = {
    { AI_ADDRCONFIG,   "addrconfig"  },
    { AI_V4MAPPED,     "v4mapped"    },
    { AI_ALL,          "all"         },
    { AI_NUMERICHOST,  "numerichost" },
    { AI_PASSIVE,      "passive"     },
    { AI_NUMERICSERV,  "numericserv" },
    { AI_CANONNAME,    "canonname"   },

    //! @todo extend/check list

    { 0, NULL }
  };

  lluv_loop_t *loop = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  int argc = loop ? 1 : 0;
  int hi = 0;
  if(!loop)loop = lluv_default_loop(L);
  {
    const char *node;
    const char *service = NULL;
    lluv_req_t *req; int err;
    struct addrinfo hints;

    memset(&hints, 0, sizeof(hints));

    node = luaL_optstring(L, argc + 1, NULL);

    if(!lua_isfunction(L, argc + 2))
      if(lua_istable(L, argc + 2)) hi = argc + 2;
      else service = luaL_optstring(L, argc + 2, NULL);

    luaL_argcheck(L, node || service, argc + 1, "you must specify node or service");
    
    if(!hi && lua_istable(L, argc + 3)) hi = argc + 3;

    if(hi){
      lua_getfield(L, hi, "family");
      hints.ai_family = lluv_opt_named_const(L, -1, 0, ai_family);
      lua_pop(L, 1);

      lua_getfield(L, hi, "socktype");
      hints.ai_socktype = lluv_opt_named_const(L, -1, 0, ai_stype);
      lua_pop(L, 1);

      lua_getfield(L, hi, "protocol");
      hints.ai_protocol = lluv_opt_named_const(L, -1, 0, ai_proto);
      lua_pop(L, 1);

      lua_getfield(L, hi, "flags");
      hints.ai_flags = lluv_opt_flags_ui(L, -1, 0, FLAGS);
      lua_pop(L, 1);
    }
    


    lluv_check_args_with_cb(L, argc + 4);
    req = lluv_req_new(L, UV_GETADDRINFO, NULL);

    err = uv_getaddrinfo(loop->handle, LLUV_R(req, getaddrinfo), lluv_on_getaddrinfo, node, service, &hints);
    if(err < 0){
      lluv_req_free(L, req);
      return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
    }
  }
  lua_settop(L, 0);
  lluv_loop_pushself(L, loop);
  return 1;
}

static int lluv_getnameinfo(lua_State *L){
  static const lluv_uv_const_t FLAGS[] = {
    { NI_NOFQDN,        "nofqdn"       },
    { NI_NUMERICHOST,   "numerichost"  },
    { NI_NAMEREQD,      "namereqd"     },
    { NI_NUMERICSERV,   "numericserv"  },
    { NI_DGRAM,         "dgram"        },

    { 0, NULL }
  };

  lluv_loop_t *loop = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  int argc = loop ? 1 : 0;
  if(!loop)loop = lluv_default_loop(L);
  {
    struct sockaddr_storage sa;
    int err; unsigned int flags = 0;
    lluv_req_t *req;

    if(!lua_isnumber(L, argc + 2)){
      lua_pushinteger(L, 0);
      lua_insert(L, argc + 2);
    }

    err = lluv_check_addr(L, argc + 1, &sa);
    if(err < 0){
      return lluv_fail(L, loop->flags, LLUV_ERR_UV, err, lua_tostring(L, -1));
    }
    
    if(!lua_isfunction(L, argc + 3))
      flags = lluv_opt_flags_ui(L, 4, 0, FLAGS);

    lluv_check_args_with_cb(L, argc + 4);
    req = lluv_req_new(L, UV_GETNAMEINFO, NULL);

    err = uv_getnameinfo(loop->handle, LLUV_R(req, getnameinfo), lluv_on_getnameinfo, (struct sockaddr*)&sa, flags);
    if(err < 0){
      lluv_req_free(L, req);
      return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
    }
  }
  lua_settop(L, 0);
  lluv_loop_pushself(L, loop);
  return 1;
}

static const lluv_uv_const_t lluv_dns_constants[] = {
  { NI_NOFQDN,        "NI_NOFQDN"       },
  { NI_NUMERICHOST,   "NI_NUMERICHOST"  },
  { NI_NAMEREQD,      "NI_NAMEREQD"     },
  { NI_NUMERICSERV,   "NI_NUMERICSERV"  },
  { NI_DGRAM,         "NI_DGRAM"        },

  { 0, NULL }
};

static const struct luaL_Reg lluv_dns_functions[] = {
  {"getaddrinfo", lluv_getaddrinfo},
  {"getnameinfo", lluv_getnameinfo},

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_dns_initlib(lua_State *L, int nup){
  luaL_setfuncs(L, lluv_dns_functions, nup);
  lluv_register_constants(L, lluv_dns_constants);
}