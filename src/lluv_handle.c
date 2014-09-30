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
#include "lluv_idle.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include "lluv_tcp.h"
#include <assert.h>

static int lluv_handle_dispatch(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);
  luaL_checkstring(L, 2);

  switch(handle->handle->type){
    case UV_HANDLE: return lluv_handle_index(L);
    case UV_IDLE:   return lluv_idle_index(L);
    case UV_TIMER:  return lluv_timer_index(L);
    case UV_TCP:    return lluv_tcp_index(L);
  }
  assert(0 && "please provive index function for this handle type");
  return 0;
}

//{ Handle

#define LLUV_HANDLE_NAME LLUV_PREFIX" Handle"
static const char *LLUV_HANDLE = LLUV_HANDLE_NAME;

LLUV_INTERNAL int lluv_handle_index(lua_State *L){
  return lluv__index(L, LLUV_HANDLE, NULL);
}

static int lluv_handle_cb_count(uv_handle_type type){
  switch(type){
    case UV_HANDLE     : return 1;
    case UV_IDLE       : return 2;
    case UV_TIMER      : return 2;
    case UV_ASYNC      : return 2;
    case UV_CHECK      : return 2;
    case UV_FS_EVENT   : return 2;
    case UV_FS_POLL    : return 2;
    case UV_NAMED_PIPE : return 6;
    case UV_POLL       : return 2;
    case UV_PREPARE    : return 2;
    case UV_PROCESS    : return 2;
    case UV_STREAM     : return 6;
    case UV_TCP        : return 6;
    case UV_TTY        : return 6;
    case UV_UDP        : return 3;
    case UV_SIGNAL     : return 2;
    default: return 0;
  }
}

LLUV_INTERNAL uv_handle_t* lluv_handle_create(lua_State *L, uv_handle_type type, lluv_flags_t flags){
  size_t cb = lluv_handle_cb_count(type), size = uv_handle_size(type);
  size_t i = 0;
  lluv_handle_t *handle;

  handle = lutil_newudatap_impl(L, sizeof(lluv_handle_t) + (sizeof(int) * (cb-1)), LLUV_HANDLE);

  handle->handle = lluv_alloc(L, size);
  if(!handle->handle) return NULL;

  handle->L      = L;
  handle->flags  = flags | LLUV_FLAG_OPEN;
  handle->handle->data = handle;
  for(i = 0; i < cb; ++i){
    handle->callbacks[i] = LUA_NOREF;
  }

  lua_pushvalue(L, -1);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, handle->handle);

  return handle->handle;
}

LLUV_INTERNAL lluv_handle_t* lluv_check_handle(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = (lluv_handle_t *)lutil_checkudatap (L, idx, LLUV_HANDLE);
  luaL_argcheck (L, handle != NULL, idx, LLUV_HANDLE_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_HANDLE_NAME" closed");
  return handle;
}

LLUV_INTERNAL void lluv_handle_cleanup(lua_State *L, lluv_handle_t *handle){
  int i, cb = lluv_handle_cb_count(handle->handle->type);

  FLAG_UNSET(handle, LLUV_FLAG_OPEN);
  for(i = 0; i < cb; ++i){
    luaL_unref(L,  LLUV_LUA_REGISTRY, handle->callbacks[i]);
    handle->callbacks[i] = LUA_NOREF;
  }
  lua_pushnil(L);
  lua_rawsetp(L, LLUV_LUA_REGISTRY, handle->handle);
  lluv_free(L, handle->handle);
  handle->handle = NULL;
}

static void lluv_on_handle_close(uv_handle_t *arg){
  lluv_handle_t *handle = arg->data;
  lua_State *L = handle->L;
  int top = lua_gettop(L);

  assert(arg == handle->handle);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_CLOSE_CB(handle));
  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle);

  assert(handle == lua_touserdata(L, -1));

  lluv_handle_cleanup(L, handle);

  if(!lua_isnil(L, -2))
    lluv_lua_call(L, 1, 0);

  lua_settop(L, top);
}

static int lluv_handle_close(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);

  if(uv_is_closing(handle->handle)){
    return 0;
  }

  lua_settop(L, 2);
  if(lua_isfunction(L, 2)){
    LLUV_CLOSE_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);
  }

  uv_close(handle->handle, lluv_on_handle_close);
  return 0;
}

static int lluv_handle_to_s(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);
  if(FLAGS_IS_SET(handle, LLUV_FLAG_OPEN)){
    switch (handle->handle->type) {
#define XX(uc, lc) case UV_##uc: \
      lua_pushfstring(L, LLUV_PREFIX " " #lc " (%p)", handle);\
      break;

      UV_HANDLE_TYPE_MAP(XX)

#undef XX
      default: lua_pushstring(L, "UNKNOWN"); break;
    }
  }
  else{
    lua_pushfstring(L, LLUV_PREFIX " Closed handle (%p)", handle);
  }
  return 1;
}

static int lluv_handle_loop(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_rawgetp(L, LLUV_LUA_REGISTRY, handle->handle->loop);
  return 1;
}

static int lluv_handle_ref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_ref(handle->handle);
  return 0;
}

static int lluv_handle_unref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_unref(handle->handle);
  return 0;
}

static int lluv_handle_has_ref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_has_ref(handle->handle));
  return 1;
}

static int lluv_handle_is_active(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_is_active(handle->handle));
  return 1;
}

static int lluv_handle_is_closing(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_is_closing(handle->handle));
  return 1;
}

static int lluv_handle_send_buffer_size(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  int size = luaL_optint(L, 2, 0);
  int err = uv_send_buffer_size(handle->handle, &size);
  if(err<0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  if(size) lua_pushinteger(L, size);
  else lua_pushboolean(L, 1);
  return 1;
}

static int lluv_handle_recv_buffer_size(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  int size = luaL_optint(L, 2, 0);
  int err = uv_recv_buffer_size(handle->handle, &size);
  if(err<0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  if(size) lua_pushinteger(L, size);
  else lua_pushboolean(L, 1);
  return 1;
}

#ifdef LLUV_UV_HAS_FILENO
static int lluv_handle_fileno(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_os_fd_t fd;
  int err = uv_fileno(handle->handle, &fd);
  if(err<0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  lutil_pushint64(L, fd);
  return 1;
}
#endif

static const struct luaL_Reg lluv_handle_methods[] = {
  { "__gc",             lluv_handle_close            },
  { "__index",          lluv_handle_dispatch         },
  { "__tostring",       lluv_handle_to_s             },
  { "loop",             lluv_handle_loop             },
  { "close",            lluv_handle_close            },
  { "ref",              lluv_handle_ref              },
  { "unref",            lluv_handle_unref            },
  { "has_ref",          lluv_handle_has_ref          },
  { "is_active",        lluv_handle_is_active        },
  { "is_closing",       lluv_handle_is_closing       },
  { "send_buffer_size", lluv_handle_send_buffer_size },
  { "recv_buffer_size", lluv_handle_recv_buffer_size },
#ifdef LLUV_UV_HAS_FILENO
  { "fileno",           lluv_handle_fileno           },
#endif

  {NULL,NULL}
};

//}

static const struct luaL_Reg lluv_handle_functions[] = {

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_handle_initlib(lua_State *L, int nup){
  int ret;
  lutil_pushnvalues(L, nup);

  ret = lutil_newmetatablep(L, LLUV_HANDLE);
  lua_insert(L, -1 - nup); /* move mt prior upvalues */
  if(ret) luaL_setfuncs (L, lluv_handle_methods, nup);
  else lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_handle_functions, nup);
}
