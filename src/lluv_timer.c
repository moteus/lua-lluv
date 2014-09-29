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
#include "lluv_timer.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include <assert.h>

#define LLUV_TIMER_NAME LLUV_PREFIX" Timer"
static const char *LLUV_TIMER = LLUV_TIMER_NAME;

LLUV_INTERNAL int lluv_timer_index(lua_State *L){
  return lluv__index(L, LLUV_TIMER, lluv_handle_index);
}

static int lluv_timer_create(lua_State *L){
  uv_timer_t *timer  = (uv_timer_t *)lluv_handle_create(L, UV_TIMER, 0);
  lluv_loop_t *loop  = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);
  if(!loop) loop = lluv_default_loop(L);
  uv_timer_init(loop->handle, timer);
  return 1;
}

static lluv_handle_t* lluv_check_timer(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_chek_handle(L, 1, LLUV_FLAG_OPEN);
  luaL_argcheck (L, handle->handle->type == UV_TIMER, 1, LLUV_TIMER_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_TIMER_NAME" closed");
  return handle;
}

static void lluv_on_timer_start(uv_timer_t *arg){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;
  int top = lua_gettop(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_START_CB(handle));

  if(!lua_isnil(L, -1)){
    lua_rawgetp(L, LLUV_LUA_REGISTRY, arg);
    lluv_lua_call(L, 1, 0);
  }

  lua_settop(L, top);
}

static int lluv_timer_start(lua_State *L){
  lluv_handle_t *handle = lluv_check_timer(L, 1, LLUV_FLAG_OPEN);
  uint64_t timeout, repeat;
  int err;

  lluv_check_none(L, 5);
  lluv_check_callable(L, -1);

  LLUV_START_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  if(lua_gettop(L) > 1){
    timeout = lutil_checkint64(L, 2);
    if(lua_gettop(L) > 2)
      repeat = lutil_checkint64(L, 3);
    else
      repeat = 0;
  }
  else{
    timeout = 0;
    repeat  = 0;
  }

  err = uv_timer_start((uv_timer_t*)handle->handle, lluv_on_timer_start, timeout, repeat);
  if(err < 0){
    return lluv_fail(L, LLUV_ERROR_RETURN, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_timer_stop(lua_State *L){
  lluv_handle_t *handle = lluv_check_timer(L, 1, LLUV_FLAG_OPEN);
  int err = uv_timer_stop((uv_timer_t*)handle->handle);
  if(err < 0){
    return lluv_fail(L, LLUV_ERROR_RETURN, LLUV_ERR_UV, err, NULL);
  }
  lua_settop(L, 1);
  return 1;
}

static int lluv_timer_again(lua_State *L){
  lluv_handle_t *handle = lluv_check_timer(L, 1, LLUV_FLAG_OPEN);
  int err = uv_timer_again((uv_timer_t*)handle->handle);
  if(err < 0){
    return lluv_fail(L, LLUV_ERROR_RETURN, LLUV_ERR_UV, err, NULL);
  }
  lua_settop(L, 1);
  return 1;
}

static int lluv_timer_set_repeat(lua_State *L){
  lluv_handle_t *handle = lluv_check_timer(L, 1, LLUV_FLAG_OPEN);
  uint64_t repeat = lutil_optint64(L, 2, 0);
  uv_timer_set_repeat((uv_timer_t*)handle->handle, repeat);
  lua_settop(L, 1);
  return 1;
}

static int lluv_timer_get_repeat(lua_State *L){
  lluv_handle_t *handle = lluv_check_timer(L, 1, LLUV_FLAG_OPEN);
  uint64_t repeat = uv_timer_get_repeat((uv_timer_t*)handle->handle);
  lutil_pushint64(L, repeat);
  return 1;
}

static const struct luaL_Reg lluv_timer_methods[] = {
  { "start",      lluv_timer_start      },
  { "stop",       lluv_timer_stop       },
  { "again",      lluv_timer_again      },
  { "set_repeat", lluv_timer_set_repeat },
  { "get_repeat", lluv_timer_get_repeat },

  {NULL,NULL}
};

static const struct luaL_Reg lluv_timer_functions[] = {
  { "timer",      lluv_timer_create     },

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_timer_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_TIMER, lluv_timer_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_timer_functions, nup);
}
