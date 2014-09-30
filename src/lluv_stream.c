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

LLUV_IMPLEMENT_XXX_REQ(connect, LLUV_INTERNAL)

LLUV_IMPLEMENT_XXX_REQ(shutdown, static)

LLUV_IMPLEMENT_XXX_REQ(write, static)

#define LLUV_STREAM_NAME LLUV_PREFIX" Stream"
static const char *LLUV_STREAM = LLUV_STREAM_NAME;

LLUV_INTERNAL int lluv_stream_index(lua_State *L){
  return lluv__index(L, LLUV_STREAM, lluv_handle_index);
}

LLUV_INTERNAL uv_handle_t* lluv_stream_create(lua_State *L, uv_handle_type type, lluv_flags_t flags){
  uv_handle_t *handle  = lluv_handle_create(L, type, flags | LLUV_FLAG_STREAM);

  assert( (type == UV_TCP) || (type == UV_NAMED_PIPE) || (type == UV_TTY) );

  return handle;
}

LLUV_INTERNAL lluv_handle_t* lluv_check_stream(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_check_handle(L, idx, flags);
  luaL_argcheck (L, IS_(handle, STREAM), idx, LLUV_STREAM_NAME" expected");

  return handle;
}

LLUV_INTERNAL void lluv_on_stream_connect_cb(uv_connect_t* arg, int status){
  lluv_connect_t *req = arg->data;
  lluv_handle_t *handle = req->handle;
  lua_State *L = handle->L;

  if(!IS_(handle, OPEN)){
    lluv_connect_free(L, req);
    return;
  }
  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);
  lluv_connect_free(L, req);

  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);
  if(status >= 0) lua_pushnil(L);
  else lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);

  lluv_lua_call(L, 2, 0);
}

//{ Shutdown

static void lluv_on_stream_shutdown_cb(uv_shutdown_t* arg, int status){
  lluv_shutdown_t *req  = arg->data;
  lluv_handle_t *handle = req->handle;
  lua_State *L = handle->L;

  if(!IS_(handle, OPEN)){
    lluv_shutdown_free(L, req);
    return;
  }
  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);
  lluv_shutdown_free(L, req);

  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);
  if(status >= 0) lua_pushnil(L);
  else lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);

  lluv_lua_call(L, 2, 0);
}

static int lluv_stream_shutdown(lua_State *L){
  lluv_handle_t  *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  lluv_shutdown_t *req;
  int err;

  lluv_check_args_with_cb(L, 2);

  req = lluv_shutdown_new(L, handle);

  err = uv_shutdown(&req->req, (uv_stream_t*)handle->handle, lluv_on_stream_shutdown_cb);
  if(err < 0){
    lluv_shutdown_free(L, req);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

//}

//{ Listen

static void lluv_on_stream_connection_cb(uv_stream_t* arg, int status){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;

  if(!IS_(handle, OPEN)){
    return;
  }

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_CONNECTION_CB(handle));
  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);
  if(status >= 0) lua_pushnil(L);
  else lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);

  lluv_lua_call(L, 2, 0);
}

static int lluv_stream_listen(lua_State *L){
  lluv_handle_t  *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  int backlog = 511; /* http://blog.dubbelboer.com/2012/04/09/syn-cookies.html */
  int err;

  if(lua_gettop(L) > 2) backlog = luaL_checkint(L, 2);
  lluv_check_args_with_cb(L, 3);
  LLUV_CONNECTION_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  err = uv_listen((uv_stream_t*)handle->handle, backlog, lluv_on_stream_connection_cb);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

static int lluv_stream_accept(lua_State *L){
  lluv_handle_t  *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  lluv_handle_t  *dst    = lluv_check_handle(L, 2, LLUV_FLAG_OPEN);
  int err;
  lua_settop(L, 2);

  err = uv_accept((uv_stream_t*)handle->handle, (uv_stream_t*)dst->handle);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  return 1;
}

//}

//{ Read

static void lluv_on_stream_read_cb(uv_stream_t* arg, int nread, const uv_buf_t* buf){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;

  assert((uv_handle_t*)arg == handle->handle);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));
  assert(!lua_isnil(L, -1));

  lua_rawgetp(L, LLUV_LUA_REGISTRY, arg);
  assert(handle == lua_touserdata(L, -1));

  if(nread >= 0){
    lua_pushnil(L);
    lua_pushlstring(L, buf->base, nread);
    lluv_free_buffer((uv_handle_t*)arg, buf);
  }
  else{
    lluv_free_buffer((uv_handle_t*)arg, buf);

    /* The callee is responsible for stopping closing the stream 
     *  when an error happens by calling uv_read_stop() or uv_close().
     *  Trying to read from the stream again is undefined.
     */
    uv_read_stop(arg);

    luaL_unref(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));
    LLUV_READ_CB(handle) = LUA_NOREF;

    lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)nread, NULL);
    lua_pushnil(L);
  }

  lluv_lua_call(L, 3, 0);
}

static int lluv_stream_start_read(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  int err;

  lluv_check_args_with_cb(L, 2);
  LLUV_READ_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);

  err = uv_read_start((uv_stream_t*)handle->handle, lluv_alloc_buffer_cb, lluv_on_stream_read_cb);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
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
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  luaL_unref(L, LLUV_LUA_REGISTRY, LLUV_READ_CB(handle));
  LLUV_READ_CB(handle) = LUA_NOREF;

  lua_settop(L, 1);
  return 1;
}

//}

//{ Write

static int lluv_stream_try_write(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  size_t len; const char *str = luaL_checklstring(L, 2, &len);
  int err; uv_buf_t buf = uv_buf_init((char*)str, len);

  lluv_check_none(L, 3);

  err = uv_try_write((uv_stream_t*)handle->handle, &buf, 1);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_pushinteger(L, err);
  return 1;
}

static void lluv_on_stream_write_cb(uv_write_t* arg, int status){
  lluv_write_t  *req    = arg->data;
  lluv_handle_t *handle = req->handle;
  lua_State *L          = handle->L;

  /* release write data (e.g. Lua string */
  lua_pushnil(L);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, &req->req);

  if(!IS_(handle, OPEN)){
    lluv_write_free(L, req);
    return;
  }

  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);
  lluv_write_free(L, req);
  assert(!lua_isnil(L, -1));

  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);
  if(status >= 0) lua_pushnil(L);
  else lluv_error_create(L, LLUV_ERR_UV, (uv_errno_t)status, NULL);

  lluv_lua_call(L, 2, 0);
}

static int lluv_stream_write(lua_State *L){
  lluv_handle_t  *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  size_t len; const char *str = luaL_checklstring(L, 2, &len);
  int err; lluv_write_t *req;
  uv_buf_t buf = uv_buf_init((char*)str, len);

  lluv_check_args_with_cb(L, 3);

  req = lluv_write_new(L, handle);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, &req->req); /* string */

  err = uv_write(&req->req, (uv_stream_t*)handle->handle, &buf, 1, lluv_on_stream_write_cb);
  if(err < 0){
    lua_pushnil(L);
    lua_rawsetp(L, LLUV_LUA_REGISTRY, &req->req);
    lluv_write_free(L, req);
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  lua_settop(L, 1);
  return 1;
}

//}

static int lluv_stream_is_readable(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  lua_settop(L, 1);
  lua_pushboolean(L, uv_is_readable((uv_stream_t*) handle->handle));
  return 1;
}

static int lluv_stream_is_writable(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  lua_settop(L, 1);
  lua_pushboolean(L, uv_is_writable((uv_stream_t*) handle->handle));
  return 1;
}

static int lluv_stream_set_blocking(lua_State *L){
  lluv_handle_t *handle = lluv_check_stream(L, 1, LLUV_FLAG_OPEN);
  int block = luaL_opt(L, lua_toboolean, 2, 1);
  int err;

  lua_settop(L, 1);

  err = uv_stream_set_blocking((uv_stream_t*)handle->handle, block);
  if(err < 0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }

  return 1;
}

static const struct luaL_Reg lluv_stream_methods[] = {
  { "shutdown",     lluv_stream_shutdown      },
  { "listen",       lluv_stream_listen        },
  { "accept",       lluv_stream_accept        },
  { "start_read",   lluv_stream_start_read    },
  { "stop_read",    lluv_stream_stop_read     },
  { "try_write",    lluv_stream_try_write     },
  { "write",        lluv_stream_write         },
  { "is_readable",  lluv_stream_is_readable   },
  { "is_writable",  lluv_stream_is_writable   },
  { "set_blocking", lluv_stream_set_blocking  },
  
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
