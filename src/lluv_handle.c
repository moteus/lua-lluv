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
#include "lluv_timer.h"
#include "lluv_idle.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include "lluv_tcp.h"
#include "lluv_pipe.h"
#include "lluv_tty.h"
#include "lluv_udp.h"
#include "lluv_prepare.h"
#include "lluv_check.h"
#include "lluv_poll.h"
#include "lluv_signal.h"
#include "lluv_fs_event.h"
#include "lluv_fs_poll.h"
#include "lluv_process.h"
#include <assert.h>

static int lluv_handle_dispatch(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);
  luaL_checkstring(L, 2);

  switch(handle->handle.type){
    case UV_HANDLE:     return lluv_handle_index(L);
    case UV_STREAM:     return lluv_stream_index(L);
    case UV_IDLE:       return lluv_idle_index(L);
    case UV_TIMER:      return lluv_timer_index(L);
    case UV_TCP:        return lluv_tcp_index(L);
    case UV_NAMED_PIPE: return lluv_pipe_index(L);
    case UV_TTY:        return lluv_tty_index(L);
    case UV_UDP:        return lluv_udp_index(L);
    case UV_PREPARE:    return lluv_prepare_index(L);
    case UV_CHECK:      return lluv_check_index(L);
    case UV_POLL:       return lluv_poll_index(L);
    case UV_SIGNAL:     return lluv_signal_index(L);
    case UV_FS_EVENT:   return lluv_fs_event_index(L);
    case UV_FS_POLL:    return lluv_fs_poll_index(L);
    case UV_PROCESS:    return lluv_process_index(L);
  }
  assert(0 && "please provide index function for this handle type");
  return 0;
}

//{ Handle

#define LLUV_HANDLE_NAME LLUV_PREFIX" Handle"
static const char *LLUV_HANDLE = LLUV_HANDLE_NAME;

static int lluv_handle_set_data(lua_State *L);

static int lluv_handle_get_data(lua_State *L);

LLUV_INTERNAL int lluv_handle_index(lua_State *L){
  const char *key = luaL_checkstring(L, 2);
  if(0 == strcmp("data", key)){
    lua_remove(L, 2);
    return lluv_handle_get_data(L);
  }

  return lluv__index(L, LLUV_HANDLE, NULL);
}

LLUV_INTERNAL int lluv_handle_newindex(lua_State *L){
  const char *key = luaL_checkstring(L, 2);
  if(0 == strcmp("data", key)){
    lua_remove(L, 2);
    return lluv_handle_set_data(L);
  }

  lua_pushfstring(L, "can not set field `%s` to userdata", key);
  return lua_error(L);
}

LLUV_INTERNAL lluv_handle_t* lluv_handle_create(lua_State *L, uv_handle_type type, lluv_flags_t flags){
  size_t extra_size = uv_handle_size(type) - sizeof(uv_handle_t);
  lluv_handle_t *handle; int i;

  assert(uv_handle_size(type) >= sizeof(uv_handle_t));

  handle = lutil_newudatap_impl(L, sizeof(lluv_handle_t) + extra_size, LLUV_HANDLE);

  handle->L      = L;
  handle->flags  = flags | LLUV_FLAG_OPEN;
  handle->handle.data = handle;
  for(i = 0; i < LLUV_MAX_HANDLE_CB; ++i){
    handle->callbacks[i] = LUA_NOREF;
  }

  handle->ud_ref = LUA_NOREF;

  lua_pushvalue(L, -1);
  handle->self = luaL_ref(L, LLUV_LUA_REGISTRY);

  return handle;
}

LLUV_INTERNAL lluv_handle_t* lluv_check_handle(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = (lluv_handle_t *)lutil_checkudatap (L, idx, LLUV_HANDLE);
  luaL_argcheck (L, handle != NULL, idx, LLUV_HANDLE_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_HANDLE_NAME" closed");
  return handle;
}

LLUV_INTERNAL lluv_handle_t* lluv_handle_byptr(uv_handle_t *h){
  size_t off = offsetof(lluv_handle_t, handle);
  lluv_handle_t *handle = (lluv_handle_t *)(((char*)h) - off);
  assert(handle == h->data);
  return handle;
}

LLUV_INTERNAL int lluv_handle_push(lua_State *L, uv_handle_t *h){
  lluv_handle_t *handle = lluv_handle_byptr(h);
  lua_rawgeti(L, LLUV_LUA_REGISTRY, handle->self);
  assert(handle == lua_touserdata(L, -1));
  return 1;
}

LLUV_INTERNAL int lluv_handle_pushself(lua_State *L, lluv_handle_t *handle){
  lua_rawgeti(L, LLUV_LUA_REGISTRY, handle->self);
  assert(handle == lua_touserdata(L, -1));
  return 1;
}

LLUV_INTERNAL void lluv_handle_cleanup(lua_State *L, lluv_handle_t *handle){
  int i;
  FLAG_UNSET(handle, LLUV_FLAG_OPEN);
  for(i = 0; i < LLUV_MAX_HANDLE_CB; ++i){
    luaL_unref(L,  LLUV_LUA_REGISTRY, handle->callbacks[i]);
    handle->callbacks[i] = LUA_NOREF;
  }
  luaL_unref(L, LLUV_LUA_REGISTRY, handle->self);
  luaL_unref(L, LLUV_LUA_REGISTRY, handle->ud_ref);
  handle->self = handle->ud_ref = LUA_NOREF;
}

static void lluv_on_handle_close(uv_handle_t *arg){
  lluv_handle_t *handle = lluv_handle_byptr(arg);
  lua_State *L = LLUV_HCALLBACK_L(handle);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  if(!IS_(handle, OPEN))return; //! @check is it possible?

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_CLOSE_CB(handle));
  lluv_handle_pushself(L, handle);

  lluv_handle_cleanup(L, handle);

  if(lua_isnil(L, -2)) lua_pop(L, 2);
  else lluv_lua_call(L, 1, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static int lluv_handle_close(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);

  if(!IS_(handle, OPEN)){
    return 0;
  }

  if(uv_is_closing(LLUV_H(handle, uv_handle_t))){
    return 0;
  }

  lua_settop(L, 2);
  if(lua_isfunction(L, 2)){
    LLUV_CLOSE_CB(handle) = luaL_ref(L, LLUV_LUA_REGISTRY);
  }

  uv_close(LLUV_H(handle, uv_handle_t), lluv_on_handle_close);

  lua_settop(L, 1);
  return 1;
}

static int lluv_handle_closed(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);

  lua_pushboolean(L, IS_(handle, OPEN) ? 0 : 1);
  return 1;
}

static int lluv_handle_to_s(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, 0);
  if(FLAGS_IS_SET(handle, LLUV_FLAG_OPEN)){
    switch (LLUV_H(handle, uv_handle_t)->type) {
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
  lua_rawgetp(L, LLUV_LUA_REGISTRY, LLUV_H(handle, uv_handle_t)->loop);
  return 1;
}

static int lluv_handle_ref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_ref(LLUV_H(handle, uv_handle_t));
  lua_settop(L, 1);
  return 1;
}

static int lluv_handle_unref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_unref(LLUV_H(handle, uv_handle_t));
  lua_settop(L, 1);
  return 1;
}

static int lluv_handle_has_ref(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_has_ref(LLUV_H(handle, uv_handle_t)));
  return 1;
}

static int lluv_handle_is_active(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_is_active(LLUV_H(handle, uv_handle_t)));
  return 1;
}

static int lluv_handle_is_closing(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_pushboolean(L, uv_is_closing(LLUV_H(handle, uv_handle_t)));
  return 1;
}

static int lluv_handle_send_buffer_size(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  int size = luaL_optint(L, 2, 0);
  int err = uv_send_buffer_size(LLUV_H(handle, uv_handle_t), &size);
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
  int err = uv_recv_buffer_size(LLUV_H(handle, uv_handle_t), &size);
  if(err<0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  if(size) lua_pushinteger(L, size);
  else lua_pushboolean(L, 1);
  return 1;
}

static int lluv_handle_fileno(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  uv_os_fd_t fd;
  int err = uv_fileno(LLUV_H(handle, uv_handle_t), &fd);
  if(err<0){
    return lluv_fail(L, handle->flags, LLUV_ERR_UV, err, NULL);
  }
  lutil_pushint64(L, fd);
  return 1;
}

static int lluv_handle_set_data(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_settop(L, 2);
  luaL_unref(L, LLUV_LUA_REGISTRY, handle->ud_ref);
  handle->ud_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  return 0;
}

static int lluv_handle_get_data(lua_State *L){
  lluv_handle_t *handle = lluv_check_handle(L, 1, LLUV_FLAG_OPEN);
  lua_rawgeti(L, LLUV_LUA_REGISTRY, handle->ud_ref);
  return 1;
}

static const struct luaL_Reg lluv_handle_methods[] = {
  { "__gc",             lluv_handle_close            },
  { "__index",          lluv_handle_dispatch         },
  { "__newindex",       lluv_handle_newindex         },
  { "__tostring",       lluv_handle_to_s             },
  { "loop",             lluv_handle_loop             },
  { "close",            lluv_handle_close            },
  { "closed",           lluv_handle_closed           },
  { "ref",              lluv_handle_ref              },
  { "unref",            lluv_handle_unref            },
  { "has_ref",          lluv_handle_has_ref          },
  { "is_active",        lluv_handle_is_active        },
  { "is_closing",       lluv_handle_is_closing       },
  { "send_buffer_size", lluv_handle_send_buffer_size },
  { "recv_buffer_size", lluv_handle_recv_buffer_size },
  { "fileno",           lluv_handle_fileno           },

  {NULL,NULL}
};

//}

LLUV_INTERNAL void lluv_on_handle_start(uv_handle_t *arg){
  lluv_handle_t *handle = lluv_handle_byptr(arg);
  lua_State *L = LLUV_HCALLBACK_L(handle);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, LLUV_START_CB(handle));
  assert(!lua_isnil(L, -1)); /* is callble */

  lluv_handle_pushself(L, handle);
  lluv_lua_call(L, 1, 0);

  LLUV_CHECK_LOOP_CB_INVARIANT(L);
}

static const struct luaL_Reg lluv_handle_functions[] = {

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_handle_initlib(lua_State *L, int nup, int safe){
  int ret;
  lutil_pushnvalues(L, nup);

  ret = lutil_newmetatablep(L, LLUV_HANDLE);
  lua_insert(L, -1 - nup); /* move mt prior upvalues */
  if(ret) luaL_setfuncs (L, lluv_handle_methods, nup);
  else lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_handle_functions, nup);
}
