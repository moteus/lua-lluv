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

static lluv_handle_t* lluv_check_stream(lua_State *L, int idx, lluv_flags_t flags){
  lluv_handle_t *handle = lluv_chek_handle(L, idx, LLUV_FLAG_OPEN);
  luaL_argcheck (L, SET_(handle, STREAM), idx, LLUV_STREAM_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(handle, flags), idx, LLUV_STREAM_NAME" closed");
  return handle;
}

static const struct luaL_Reg lluv_stream_methods[] = {

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
