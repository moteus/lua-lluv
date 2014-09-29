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
#include "lluv_error.h"
#include "lluv_loop.h"
#include "lluv_handle.h"
#include "lluv_loop.h"
#include <assert.h>

const char *LLUV_MEMORY_ERROR_MARK = LLUV_PREFIX" Error mark";

LLUV_INTERNAL void* lluv_alloc(lua_State* L, size_t size){
  (void)L;
  return malloc(size);
}

LLUV_INTERNAL void lluv_free(lua_State* L, void *ptr){
  (void)L;
  free(ptr);
}

LLUV_INTERNAL int lluv_lua_call(lua_State* L, int narg, int nret){
  int errh = lua_isnil(L, lua_upvalueindex(3))?0:lua_upvalueindex(3);

  int ret = lua_pcall(L, narg, nret, errh);
  if(!ret) return 0;

  if(ret == LUA_ERRMEM) lua_pushlightuserdata(L, (void*)LLUV_MEMORY_ERROR_MARK);
  lua_replace(L, lua_upvalueindex(4));
  {
    lluv_loop_t* loop = lluv_opt_loop(L, LLUV_LOOP_INDEX, 0);
    uv_stop(loop->handle);
  }
  return ret;
}

LLUV_INTERNAL int lluv__index(lua_State *L, const char *meta, lua_CFunction inherit){
  assert(lua_gettop(L) == 2);

  lutil_getmetatablep(L, meta);
  lua_pushvalue(L, 2); lua_rawget(L, -2);
  if(!lua_isnil(L, -1)) return 1;
  lua_settop(L, 2);
  if(inherit) return inherit(L);
  return 0;
}

LLUV_INTERNAL void lluv_check_callable(lua_State *L, int idx){
  idx = lua_absindex(L, idx);
  luaL_checktype(L, idx, LUA_TFUNCTION);
}

LLUV_INTERNAL void lluv_check_none(lua_State *L, int idx){
  idx = lua_absindex(L, idx);
  luaL_argcheck (L, lua_isnone(L, idx), idx, "too many parameters");
}

static lluv_loop_t* lluv_loop_by_handle(uv_handle_t* h){
  lluv_handle_t *handle = h->data;
  lluv_loop_t *loop;
  lua_rawgetp(handle->L, LLUV_LUA_REGISTRY, handle->handle->loop);
  loop = lluv_check_loop(handle->L, -1, LLUV_FLAG_OPEN);
  lua_pop(handle->L, 1);

  return loop;
}

LLUV_INTERNAL void lluv_alloc_buffer_cb(uv_handle_t* h, size_t suggested_size, uv_buf_t *buf){
  lluv_loop_t* loop     = lluv_loop_by_handle(h);
  lluv_handle_t *handle = h->data;

  UNUSED_ARG(loop);

  //! @todo 
  *buf = uv_buf_init(lluv_alloc(handle->L, suggested_size), suggested_size);
}

LLUV_INTERNAL void lluv_free_buffer(uv_handle_t* h, const uv_buf_t *buf){
  lluv_loop_t* loop     = lluv_loop_by_handle(h);
  lluv_handle_t *handle = h->data;

  UNUSED_ARG(loop);

  lluv_free(handle->L, &buf->base[0]);
  // *buf = uv_buf_init(0, 0);
}

