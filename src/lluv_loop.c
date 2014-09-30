/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#include "lluv_loop.h"
#include "lluv_error.h"
#include "lluv_utils.h"
#include "lluv_handle.h"
#include <assert.h>


#define LLUV_LOOP_NAME LLUV_PREFIX" Loop"
static const char *LLUV_LOOP = LLUV_LOOP_NAME;

static const char *LLUV_DEFAULT_LOOP_TAG = LLUV_PREFIX" default loop";

LLUV_INTERNAL lluv_loop_t* lluv_push_default_loop(lua_State *L){
  lua_rawgetp(L, LLUV_LUA_REGISTRY, LLUV_DEFAULT_LOOP_TAG);
  if(lua_isnil(L, -1)){
    lua_pop(L, 1);
    lluv_loop_create(L, uv_default_loop(), LLUV_FLAG_DEFAULT_LOOP);
    lua_pushvalue(L, -1);
    lua_rawsetp(L, LLUV_LUA_REGISTRY, LLUV_DEFAULT_LOOP_TAG);
  }
  return lluv_check_loop(L, -1, 0);
}

LLUV_INTERNAL lluv_loop_t* lluv_default_loop(lua_State *L){
  lluv_loop_t *loop = lluv_push_default_loop(L);
  lua_pop(L, 1);
  return loop;
}

LLUV_INTERNAL lluv_loop_t* lluv_ensure_loop_at(lua_State *L, int idx){
  lluv_loop_t *loop = lluv_opt_loop(L, idx, 0);
  if(loop) return loop;
  idx = lua_absindex(L, idx);
  loop = lluv_push_default_loop(L);
  lua_insert(L, idx);
  return loop;
}

LLUV_INTERNAL int lluv_loop_create(lua_State *L, uv_loop_t *h, lluv_flags_t flags){
  lluv_loop_t *loop = lutil_newudatap(L, lluv_loop_t, LLUV_LOOP);
  loop->handle       = h;
  loop->handle->data = loop;
  loop->flags        = flags | LLUV_FLAG_OPEN;
  loop->buffer_size  = LLUV_BUFFER_SIZE;
  lua_pushvalue(L, -1);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, h);
  return 1;
}

LLUV_INTERNAL lluv_loop_t* lluv_check_loop(lua_State *L, int idx, lluv_flags_t flags){
  lluv_loop_t *loop = (lluv_loop_t *)lutil_checkudatap (L, idx, LLUV_LOOP);
  luaL_argcheck (L, loop != NULL, idx, LLUV_LOOP_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(loop, flags), idx, LLUV_LOOP_NAME" closed");
  return loop;
}

LLUV_INTERNAL lluv_loop_t* lluv_opt_loop(lua_State *L, int idx, lluv_flags_t flags){
  if(!lutil_isudatap(L, idx, LLUV_LOOP)) return NULL;
  return lluv_check_loop(L, idx, flags);
}

LLUV_INTERNAL lluv_loop_t* lluv_opt_loop_ex(lua_State *L, int idx, lluv_flags_t flags){
  if(!lutil_isudatap(L, idx, LLUV_LOOP)) return lluv_default_loop(L);
  return lluv_check_loop(L, idx, flags);
}

static int lluv_loop_new_impl(lua_State *L, lluv_flags_t flags){
  uv_loop_t *loop = lluv_alloc_t(L, uv_loop_t);
  int err = uv_loop_init(loop);
  if(err < 0){
    lluv_free_t(L, uv_loop_t, loop);
    return lluv_fail(L, flags, LLUV_ERR_UV, err, NULL);
  }
  lluv_loop_create(L, loop, flags);
  return 1;
}

static int lluv_loop_new(lua_State *L){
  return lluv_loop_new_impl(L, 0);
}

static void lluv_loop_on_walk_close(uv_handle_t* handle, void* arg){
  lua_State *L = (lua_State*)arg;
  if(uv_is_closing(handle)) return;

  // if(!uv_is_active(handle)) return; // @fixme do we shold ignore this handles

  lua_settop(L, 1);

  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle);
  if(lua_isnil(L, -1)){lua_pop(L, 1); return; }

  lua_getfield(L, -1, "close");
  if(lua_isnil(L, -1)){lua_pop(L, 2); return; }

  lua_insert(L, -2);
  lua_pcall(L, 1, 0, 0);
}

static int lluv_loop_close_all_handles(lua_State *L){
  /* NOTE. if you have fs callbacks then this function
  ** would call all this function because there no handles.
  */

  lluv_loop_t* loop = lluv_check_loop(L, 1, LLUV_FLAG_OPEN);
  lua_State *arg = L;
  int err = 0;

  uv_walk(loop->handle, lluv_loop_on_walk_close, arg);
  
  while(err = uv_run(loop->handle, UV_RUN_ONCE)){
    if(err < 0)
      return lluv_fail(L, loop->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_loop_close(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, 1, 0);
  int err;

  if(!IS_(loop, OPEN)) return 0;

  if((lua_isboolean(L,2))&&(lua_toboolean(L,2))){
    int ret = lluv_loop_close_all_handles(L);
    if(ret != 1) return ret;
  }

  err = uv_loop_close(loop->handle);
  if(err < 0){
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, err, NULL);
  }

  FLAG_UNSET(loop, LLUV_FLAG_OPEN);
  lua_pushnil(L);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, loop->handle);

  if(!IS_(loop, DEFAULT_LOOP)){
    lluv_free_t(L, uv_alloc_t, loop->handle);
  }

  loop->handle = NULL;
  return 0;
}

static int lluv_loop_to_s(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, 1, 0);
  lua_pushfstring(L, LLUV_LOOP_NAME" (%p)", loop);
  return 1;
}

static int lluv_dummy_traceback(lua_State *L){
  return 1;
}

static int lluv_loop_run_impl(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, lua_upvalueindex(2), 0);
  uv_run_mode  mode = (uv_run_mode)luaL_checkinteger(L, 1);

  int err = uv_run(loop->handle, mode);
  if(err < 0){
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, err, NULL);
  }

  if(lua_touserdata(L, lua_upvalueindex(4)) == LLUV_MEMORY_ERROR_MARK){
    lua_error(L);
  }
  else if(!lua_isnil(L, lua_upvalueindex(4))){
    lua_pushvalue(L, lua_upvalueindex(4));
    lua_error(L);
  }

  lua_pushinteger(L, err);
  return 1;
}

static int lluv_loop_run(lua_State *L){
  lluv_ensure_loop_at(L, 1);

  if(lua_isnumber(L, 2)){
    luaL_checkinteger(L, 2);
  }
  else{
    if(lua_isnil(L, 2)) lua_remove(L, 2);
    lua_pushinteger(L, UV_RUN_DEFAULT);
    lua_insert(L, 2);
  }

  lua_settop(L, 3);

  if(!lua_isfunction(L,3)){
    lua_pop(L, 1);
    lua_pushcfunction(L, lluv_dummy_traceback);
  }

                    /* loop, mode, err */
  lua_insert(L, 2); /* loop, err, mode */
  lua_insert(L, 1); /* mode, loop, err  */
  lua_pushvalue(L, LLUV_LUA_REGISTRY);
  lua_insert(L, 2);/* mode, reg, loop, err  */
  lua_pushnil(L);
  lua_pushcclosure(L, lluv_loop_run_impl, 4);
  lua_insert(L, 1);
  lua_call(L, 1, LUA_MULTRET);

  return lua_gettop(L);
}

static int lluv_loop_alive(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_loop_alive(loop->handle));
  return 1;
}

static int lluv_loop_stop(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, 1, LLUV_FLAG_OPEN);
  uv_stop(loop->handle);
  return 0;
}

static int lluv_loop_now(lua_State *L){
  lluv_loop_t* loop;
  uint64_t now;
  lluv_ensure_loop_at(L, 1);
  loop = lluv_check_loop(L, 1, LLUV_FLAG_OPEN);
  now = uv_now(loop->handle);
  lutil_pushint64(L, now);
  return 1;
}

void lluv_loop_on_walk(uv_handle_t* handle, void* arg){
  lua_State *L = (lua_State*)arg;

  lua_settop(L, 2); lua_pushvalue(L, -1);
  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle);
  lua_call(L, 1, 0);
}

static int lluv_loop_walk(lua_State *L){
  lluv_loop_t* loop = lluv_check_loop(L, 1, LLUV_FLAG_OPEN);
  lua_State *arg = L;

  luaL_checktype(L, 2, LUA_TFUNCTION);

  uv_walk(loop->handle, lluv_loop_on_walk, arg);

  return 0;
}

static int lluv_push_default_loop_l(lua_State *L){
  lluv_push_default_loop(L);
  return 1;
}

static const struct luaL_Reg lluv_loop_methods[] = {
  { "__tostring", lluv_loop_to_s  },
  { "run",        lluv_loop_run   },
  { "close",      lluv_loop_close },
  { "alive",      lluv_loop_alive },
  { "stop",       lluv_loop_stop  },
  { "stop",       lluv_loop_stop  },
  { "now",        lluv_loop_now   },
  { "walk",       lluv_loop_walk  },

  { "close_all_handles", lluv_loop_close_all_handles },

  {NULL,NULL}
};

static const struct luaL_Reg lluv_loop_functions[] = {
  {"loop",         lluv_loop_new           },

  {"run",          lluv_loop_run           },
  {"now",          lluv_loop_now           },
  {"default_loop", lluv_push_default_loop_l},

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_loop_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);

  if(!lutil_createmetap(L, LLUV_LOOP, lluv_loop_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_loop_functions, nup);
}