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
#include "lluv_handle.h"
#include "lluv_stream.h"
#include "lluv_tcp.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include "lluv_req.h"
#include <assert.h>

#define LLUV_TCP_NAME LLUV_PREFIX" tcp"
static const char *LLUV_TCP = LLUV_TCP_NAME;

LLUV_INTERNAL int lluv_tcp_index(lua_State *L){
  return lluv__index(L, LLUV_TCP, lluv_stream_index);
}

static int lluv_tcp_create(lua_State *L){
  lluv_loop_t   *loop   = lluv_opt_loop_ex(L, 1, LLUV_FLAG_OPEN);
  lluv_handle_t *handle = lluv_stream_create(L, UV_TCP, INHERITE_FLAGS(loop));
  int err = uv_tcp_init(loop->handle, LLUV_H(handle, uv_tcp_t));
  if(err < 0){
    lluv_handle_cleanup(L, handle);
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
  }
  return 1;
}

static lluv_handle_t* lluv_check_tcp(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_check_stream(L, idx, LLUV_FLAG_OPEN);
  luaL_argcheck (L, LLUV_H(handle, uv_handle_t)->type == UV_TCP, idx, LLUV_TCP_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_TCP_NAME" closed");
  return handle;
}

static int lluv_tcp_connect(lua_State *L){
  lluv_handle_t  *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  const char *addr = luaL_checkstring(L, 2);
  lua_Integer port = luaL_checkint(L, 3);
  lluv_req_t *req; struct sockaddr_storage sa;
  int err = lluv_to_addr(L, addr, port, &sa);
  
  if(err < 0){
    lua_settop(L, 3);
    lua_pushliteral(L, ":");lua_insert(L, -2);lua_concat(L, 3);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, lua_tostring(L, -1));
  }

  lluv_check_args_with_cb(L, 4);

  req = lluv_req_new(L, UV_CONNECT, handle);

  err = uv_tcp_connect(LLUV_R(req, connect), LLUV_H(handle, uv_tcp_t), (struct sockaddr *)&sa, lluv_on_stream_connect_cb);
  if(err < 0){
    lluv_req_free(L, req);
    lua_settop(L, 3);
    lua_pushliteral(L, ":");lua_insert(L, -2);lua_concat(L, 3);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, lua_tostring(L, -1));
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_tcp_bind(lua_State *L){
  lluv_handle_t  *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  const char *addr  = luaL_checkstring(L, 2);
  lua_Integer port  = luaL_checkint(L, 3);
  lua_Integer flags = luaL_optint(L, 4, 0);
  struct sockaddr_storage sa;
  int err = lluv_to_addr(L, addr, port, &sa);

  lua_settop(L, 3);

  if(err < 0){
    lua_pushliteral(L, ":");lua_insert(L, -2);lua_concat(L, 3);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, lua_tostring(L, -1));
  }

  err = uv_tcp_bind(LLUV_H(handle, uv_tcp_t), (struct sockaddr *)&sa, flags);
  if(err < 0){
    lua_settop(L, 3);
    lua_pushliteral(L, ":");lua_insert(L, -2);lua_concat(L, 3);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, lua_tostring(L, -1));
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_tcp_nodelay(lua_State *L){
  lluv_handle_t *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  int enable = lua_toboolean(L, 2);
  int err = uv_tcp_nodelay(LLUV_H(handle, uv_tcp_t), enable);

  lua_settop(L, 1);

  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  return 1;
}

static int lluv_tcp_keepalive(lua_State *L){
  lluv_handle_t *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  int enable = lua_toboolean(L, 2);
  unsigned int delay = 0; int err;

  if(enable) delay = (unsigned int)luaL_checkint(L, 3);
  err = uv_tcp_keepalive(LLUV_H(handle, uv_tcp_t), enable, delay);

  lua_settop(L, 1);

  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  return 1;
}

static int lluv_tcp_simultaneous_accepts(lua_State *L){
  lluv_handle_t *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  int enable = lua_toboolean(L, 2);
  int err = uv_tcp_simultaneous_accepts(LLUV_H(handle, uv_tcp_t), enable);

  lua_settop(L, 1);

  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  return 1;
}

static int lluv_tcp_getsockname(lua_State *L){
  lluv_handle_t *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  struct sockaddr_storage sa; int sa_len = sizeof(sa);
  int err = uv_tcp_getsockname(LLUV_H(handle, uv_tcp_t), (struct sockaddr*)&sa, &sa_len);

  lua_settop(L, 1);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  return lluv_push_addr(L, &sa);
}

static int lluv_tcp_getpeername(lua_State *L){
  lluv_handle_t *handle = lluv_check_tcp(L, 1, LLUV_FLAG_OPEN);
  struct sockaddr_storage sa; int sa_len = sizeof(sa);
  int err = uv_tcp_getpeername(LLUV_H(handle, uv_tcp_t), (struct sockaddr*)&sa, &sa_len);
  lua_settop(L, 1);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  return lluv_push_addr(L, &sa);
}

static const struct luaL_Reg lluv_tcp_methods[] = {
  { "bind",                 lluv_tcp_bind                 },
  { "connect",              lluv_tcp_connect              },
  { "nodelay",              lluv_tcp_nodelay              },
  { "keepalive",            lluv_tcp_keepalive            },
  { "simultaneous_accepts", lluv_tcp_simultaneous_accepts },
  { "getsockname",          lluv_tcp_getsockname          },
  { "getpeername",          lluv_tcp_getpeername          },

  {NULL,NULL}
};

static const lluv_uv_const_t lluv_tcp_constants[] = {
  { UV_TCP_IPV6ONLY,   "TCP_IPV6ONLY"   },

  { 0, NULL }
};

static const struct luaL_Reg lluv_tcp_functions[] = {
  { "tcp", lluv_tcp_create },

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_tcp_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_TCP, lluv_tcp_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_tcp_functions, nup);
  lluv_register_constants(L, lluv_tcp_constants);
}
