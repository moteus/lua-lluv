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
#include "lluv_poll.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include <assert.h>

#define LLUV_POLL_NAME LLUV_PREFIX" Poll"
static const char *LLUV_POLL = LLUV_POLL_NAME;

LLUV_INTERNAL int lluv_poll_index(lua_State *L){
  return lluv__index(L, LLUV_POLL, lluv_handle_index);
}

static int lluv_poll_create(lua_State *L){
  lluv_loop_t *loop  = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  int fd = luaL_checkint(L, loop ? 2 : 1);
  uv_poll_t *poll; int err;

  if(!loop) loop = lluv_default_loop(L);
  poll   = (uv_poll_t *)lluv_handle_create(L, UV_POLL, INHERITE_FLAGS(loop));

  err = uv_poll_init(loop->handle, poll, fd);
  if(err < 0){
    lluv_handle_cleanup(L, (lluv_handle_t*)poll->data);
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
  }
  return 1;
}

static int lluv_poll_create_socket(lua_State *L){
  lluv_loop_t *loop  = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  uv_os_sock_t socket = (uv_os_sock_t)lutil_checkint64(L, loop ? 2 : 1);
  uv_poll_t *poll; int err;

  if(!loop) loop = lluv_default_loop(L);
  poll   = (uv_poll_t *)lluv_handle_create(L, UV_POLL, INHERITE_FLAGS(loop));

  err = uv_poll_init_socket(loop->handle, poll, socket);
  if(err < 0){
    lluv_handle_cleanup(L, (lluv_handle_t*)poll->data);
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
  }
  return 1;
}

static lluv_handle_t* lluv_check_poll(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_check_handle(L, idx, flags);
  luaL_argcheck (L, handle->handle->type == UV_POLL, idx, LLUV_POLL_NAME" expected");

  return handle;
}

static void lluv_on_poll_start(uv_poll_t *arg, int status, int events){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_START_CB(handle));
  assert(!lua_isnil(L, -1)); /* is callble */

  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);
  if(status >= 0) lua_pushnil(L);
  else lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);

  lluv_lua_call(L, 2, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static int lluv_poll_start(lua_State *L){
  lluv_handle_t *handle = lluv_check_poll(L, 1, LLUV_FLAG_OPEN);
  int events = luaL_checkint(L, 2);
  int err;

  lluv_check_args_with_cb(L, 3);
  LLUV_START_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  err = uv_poll_start((uv_poll_t*)handle->handle, events, lluv_on_poll_start);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_poll_stop(lua_State *L){
  lluv_handle_t *handle = lluv_check_poll(L, 1, LLUV_FLAG_OPEN);
  int err = uv_poll_stop((uv_poll_t*)handle->handle);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  lua_settop(L, 1);
  return 1;
}

static const struct luaL_Reg lluv_poll_methods[] = {
  { "start",      lluv_poll_start      },
  { "stop",       lluv_poll_stop       },

  {NULL,NULL}
};

static const struct luaL_Reg lluv_poll_functions[] = {
  {"poll",        lluv_poll_create},
  {"poll_socket", lluv_poll_create_socket},

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_poll_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_POLL, lluv_poll_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_poll_functions, nup);
}
