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

    lua_rawseti(L, -2, ++i);
  }

  uv_freeaddrinfo(res);
  lluv_lua_call(L, 3, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static int lluv_getaddrinfo(lua_State *L){
  lluv_loop_t *loop = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  int argc = loop ? 1 : 0;
  if(!loop)loop = lluv_default_loop(L);
  {
    const char *node;
    const char *service;
    lluv_req_t *req; int err;
    struct addrinfo hints;

    memset(&hints, 0, sizeof(hints));

    node = luaL_optstring(L, argc + 1, NULL);
    if(!lua_isfunction(L, argc + 2))
      service = luaL_optstring(L, argc + 2, NULL);
    else service = NULL;

    luaL_argcheck(L, node || service, argc + 1, "you must specify node or service");

    if(!lua_isfunction(L, argc + 3)){
      //! @todo hint
    }

    lluv_check_args_with_cb(L, argc + 4);
    req = lluv_req_new(L, UV_GETADDRINFO, NULL);

    err = uv_getaddrinfo(loop->handle, LLUV_R(req, getaddrinfo), lluv_on_getaddrinfo, node, service, NULL);
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