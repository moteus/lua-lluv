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
#include "lluv_udp.h"
#include "lluv_loop.h"
#include "lluv_error.h"
#include <assert.h>

#define LLUV_UDP_NAME LLUV_PREFIX" udp"
static const char *LLUV_UDP = LLUV_UDP_NAME;

LLUV_INTERNAL int lluv_udp_index(lua_State *L){
  return lluv__index(L, LLUV_UDP, lluv_handle_index);
}

static int lluv_udp_create(lua_State *L){
  lluv_loop_t *loop = lluv_opt_loop_ex(L, 1, LLUV_FLAG_OPEN);
  uv_udp_t *udp   = (uv_udp_t *)lluv_handle_create(L, UV_UDP, INHERITE_FLAGS(loop));
  int err = uv_udp_init(loop->handle, udp);
  if(err < 0){
    lluv_handle_cleanup(L, (lluv_handle_t*)udp->data);
    return lluv_fail(L, loop->flags, LLUV_ERR_UV, (uv_errno_t)err, NULL);
  }
  return 1;
}

static lluv_handle_t* lluv_check_udp(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_check_handle(L, idx, flags);
  luaL_argcheck (L, handle->handle->type == UV_UDP, idx, LLUV_UDP_NAME" expected");

  return handle;
}

static const struct luaL_Reg lluv_udp_methods[] = {

  {NULL,NULL}
};

static const struct luaL_Reg lluv_udp_functions[] = {

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_udp_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);
  if(!lutil_createmetap(L, LLUV_UDP, lluv_udp_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_udp_functions, nup);
}
