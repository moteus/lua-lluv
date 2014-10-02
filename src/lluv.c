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
#include "lluv_utils.h"
#include "lluv_timer.h"
#include "lluv_error.h"
#include "lluv_idle.h"
#include "lluv_loop.h"
#include "lluv_fs.h"
#include "lluv_fbuf.h"
#include "lluv_handle.h"
#include "lluv_stream.h"
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
#include "lluv_misc.h"

static const char* LLUV_REGISTRY = LLUV_PREFIX" Registry";

static const struct luaL_Reg lluv_functions[] = {

  {NULL,NULL}
};

LLUV_EXPORT_API
int luaopen_lluv(lua_State *L){
  lua_rawgetp(L, LUA_REGISTRYINDEX, LLUV_REGISTRY);
  if(!lua_istable(L, -1)){ /* registry */
    lua_pop(L, 1);
    lua_newtable(L);
  }

  lua_newtable(L); /* library  */

  lua_pushvalue(L, -2); luaL_setfuncs(L, lluv_functions, 1);
  lua_pushvalue(L, -2); lluv_error_initlib    (L, 1);
  lua_pushvalue(L, -2); lluv_loop_initlib     (L, 1);
  lua_pushvalue(L, -2); lluv_fs_initlib       (L, 1);
  lua_pushvalue(L, -2); lluv_handle_initlib   (L, 1);
  lua_pushvalue(L, -2); lluv_stream_initlib   (L, 1);
  lua_pushvalue(L, -2); lluv_timer_initlib    (L, 1);
  lua_pushvalue(L, -2); lluv_fbuf_initlib     (L, 1);
  lua_pushvalue(L, -2); lluv_idle_initlib     (L, 1);
  lua_pushvalue(L, -2); lluv_tcp_initlib      (L, 1);
  lua_pushvalue(L, -2); lluv_pipe_initlib     (L, 1);
  lua_pushvalue(L, -2); lluv_tty_initlib      (L, 1);
  lua_pushvalue(L, -2); lluv_udp_initlib      (L, 1);
  lua_pushvalue(L, -2); lluv_prepare_initlib  (L, 1);
  lua_pushvalue(L, -2); lluv_check_initlib    (L, 1);
  lua_pushvalue(L, -2); lluv_poll_initlib     (L, 1);
  lua_pushvalue(L, -2); lluv_signal_initlib   (L, 1);
  lua_pushvalue(L, -2); lluv_fs_event_initlib (L, 1);
  lua_pushvalue(L, -2); lluv_fs_poll_initlib  (L, 1);
  lua_pushvalue(L, -2); lluv_misc_initlib     (L, 1);

  lua_remove(L, -2); /* registry */

  return 1;
}
