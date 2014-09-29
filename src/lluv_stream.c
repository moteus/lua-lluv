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
#include "lluv_loop.h"
#include "lluv_error.h"
#include <assert.h>

#define LLUV_STREAM_NAME LLUV_PREFIX" Stream"
static const char *LLUV_STREAM = LLUV_STREAM_NAME;

LLUV_INTERNAL int lluv_stream_index(lua_State *L){
  return lluv__index(L, LLUV_STREAM, lluv_handle_index);
}

LLUV_INTERNAL uv_handle_t* lluv_stream_create(lua_State *L, uv_handle_type type){
  //! @todo check type argument
  uv_handle_t *handle  = lluv_handle_create(L, type, 0);
  SET_(handle, STREAM);
  return handle;
}

LLUV_INTERNAL lluv_handle_t* lluv_check_stream(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_chek_handle(L, idx, LLUV_FLAG_OPEN);
  luaL_argcheck (L, SET_(handle, STREAM), idx, LLUV_STREAM_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_STREAM_NAME" closed");
  return handle;
}

static void lluv_on_stream_read_cb(uv_stream_t* arg, int nread, const uv_buf_t* buf){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));

  if(lua_isnil(L, -1)){ /* ignore because we have no cb */
    lua_pop(L, 1);
    lluv_free_buffer((uv_handle_t*)arg, buf);
    return;
  }

  lua_rawgetp(L, LLUV_LUA_REGISTRY, arg);

  if(nread >= 0){
    lua_pushnil(L);
    lua_pushlstring(L, buf->base, nread);
    lluv_free_buffer((uv_handle_t*)arg, buf);
  }
  else{
    lluv_free_buffer((uv_handle_t*)arg, buf);
    /* Stop reading, otherwise an assert blows up on unix */
    uv_read_stop(arg);
    luaL_unref(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));
    LLUV_READ_CB(handle) = LUA_NOREF;

    lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)nread, NULL);
    lua_pushnil(L);
  }

  lluv_lua_call(L, 2, 0);
}

static int lluv_stream_start_read(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  int err;

  lluv_check_none(L, 3);
  lluv_check_callable(L, -1);

  LLUV_READ_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  err = uv_read_start((uv_stream_t*)handle->handle, lluv_alloc_buffer_cb, lluv_on_stream_read_cb);
  if(err < 0){
    return lluv_fail(L, LLUV_ERROR_RETURN, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_stream_stop_read(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  int err;
  lluv_check_none(L, 2);

  err = uv_read_stop((uv_stream_t*)handle->handle);
  if(err < 0){
    return lluv_fail(L, LLUV_ERROR_RETURN, LLUV_ERR_UV, err, NULL);
  }

  luaL_unref(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));
  LLUV_READ_CB(handle) = LUA_NOREF;

  lua_settop(L, 1);
  return 1;
}

static const struct luaL_Reg lluv_stream_methods[] = {
  { "start_read", lluv_stream_start_read },
  { "stop_read",  lluv_stream_start_read },

  {NULL,NULL}
};

static const struct luaL_Reg lluv_stream_functions[] = {

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_stream_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_STREAM, lluv_stream_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_stream_functions, nup);
}
