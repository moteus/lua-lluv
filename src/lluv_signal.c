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
#include "lluv_signal.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include <assert.h>

#define LLUV_SIGNAL_NAME LLUV_PREFIX" Signal"
static const char *LLUV_SIGNAL = LLUV_SIGNAL_NAME;

LLUV_INTERNAL int lluv_signal_index(lua_State *L){
  return lluv__index(L, LLUV_SIGNAL, lluv_handle_index);
}

LLUV_IMPL_SAFE(lluv_signal_create){
  lluv_loop_t   *loop   = lluv_opt_loop_ex(L, 1, LLUV_FLAG_OPEN);
  lluv_handle_t *handle = lluv_handle_create(L, UV_SIGNAL, INHERITE_FLAGS(loop));
  int err = uv_signal_init(loop->handle, LLUV_H(handle, uv_signal_t));
  if(err < 0){
    lluv_handle_cleanup(L, handle);
    return lluv_fail(L, safe_flag | loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
  }
  return 1;
}

static lluv_handle_t* lluv_check_signal(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_check_handle(L, idx, flags);
  luaL_argcheck (L, LLUV_H(handle, uv_handle_t)->type == UV_SIGNAL, idx, LLUV_SIGNAL_NAME" expected");

  return handle;
}

static void lluv_on_signal_start(uv_signal_t *arg, int signum){
  lluv_handle_t *handle = lluv_handle_byptr((uv_handle_t*)arg);
  lua_State *L = handle->L;

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_START_CB(handle));
  assert(!lua_isnil(L, -1)); /* is callble */

  lluv_handle_pushself(L, handle);
  lua_pushinteger(L, signum);
  lluv_lua_call(L, 2, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static int lluv_signal_start(lua_State *L){
  lluv_handle_t *handle = lluv_check_signal(L, 1, LLUV_FLAG_OPEN);
  int signum = luaL_checkint(L, 2);
  int err;

  lluv_check_args_with_cb(L, 3);
  LLUV_START_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  err = uv_signal_start(LLUV_H(handle, uv_signal_t), lluv_on_signal_start, signum);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_signal_stop(lua_State *L){
  lluv_handle_t *handle = lluv_check_signal(L, 1, LLUV_FLAG_OPEN);
  int err = uv_signal_stop(LLUV_H(handle, uv_signal_t));
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  lua_settop(L, 1);
  return 1;
}

static const struct luaL_Reg lluv_signal_methods[] = {
  { "start",      lluv_signal_start      },
  { "stop",       lluv_signal_stop       },

  {NULL,NULL}
};

static const lluv_uv_const_t lluv_signal_constants[] = {
#ifdef SIGINT
  { SIGINT,   "SIGINT"   },
#endif
#ifdef SIGBREAK
  { SIGBREAK, "SIGBREAK" },
#endif
#ifdef SIGHUP
  { SIGHUP,   "SIGHUP"   },
#endif
#ifdef SIGWINCH
  { SIGWINCH, "SIGWINCH" },
#endif
  { SIGTERM,  "SIGTERM"  },

  { 0, NULL }
};

#define LLUV_FUNCTIONS(F)       \
  {"signal", lluv_signal_create_##F}, \

static const struct luaL_Reg lluv_functions[][2] = {
  {
    LLUV_FUNCTIONS(unsafe)

    {NULL,NULL}
  },
  {
    LLUV_FUNCTIONS(safe)

    {NULL,NULL}
  },
};


LLUV_INTERNAL void lluv_signal_initlib(lua_State *L, int nup, int safe){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_SIGNAL, lluv_signal_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_functions[safe], nup);
  lluv_register_constants(L, lluv_signal_constants);
}
