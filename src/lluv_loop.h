/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_LOOP_H_
#define _LLUV_LOOP_H_

#include "lluv.h"
#include "lluv_utils.h"

#define LLUV_BUFFER_SIZE 65536

typedef struct lluv_loop_tag{
  uv_loop_t   *handle;/* read only */
  lluv_flags_t flags; /* read only */
  size_t       buffer_size;
  char         buffer[LLUV_BUFFER_SIZE];
}lluv_loop_t;

LLUV_INTERNAL void lluv_loop_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_loop_create(lua_State *L, uv_loop_t *loop, lluv_flags_t flags);

LLUV_INTERNAL lluv_loop_t* lluv_check_loop(lua_State *L, int idx, lluv_flags_t flags);

LLUV_INTERNAL lluv_loop_t* lluv_opt_loop(lua_State *L, int idx, lluv_flags_t flags);

LLUV_INTERNAL lluv_loop_t* lluv_opt_loop_ex(lua_State *L, int idx, lluv_flags_t flags);

LLUV_INTERNAL lluv_loop_t* lluv_push_default_loop(lua_State *L);

LLUV_INTERNAL lluv_loop_t* lluv_default_loop(lua_State *L);

LLUV_INTERNAL lluv_loop_t* lluv_ensure_loop_at(lua_State *L, int idx);

#endif
