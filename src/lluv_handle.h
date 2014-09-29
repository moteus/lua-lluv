/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_HANDLE_H_
#define _LLUV_HANDLE_H_

#define LLUV_CLOSE_CB(H)   H->callbacks[0]
#define LLUV_START_CB(H)   H->callbacks[1]
#define LLUV_READ_CB(H)    H->callbacks[2]

#include "lluv.h"
#include "lluv_utils.h"

typedef struct lluv_handle_tag{
  uv_handle_t *handle;
  lua_State   *L;
  lluv_flags_t flags;
  int    callbacks[1];
} lluv_handle_t;

LLUV_INTERNAL void lluv_handle_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_handle_index(lua_State *L);

LLUV_INTERNAL uv_handle_t* lluv_handle_create(lua_State *L, uv_handle_type type, lluv_flags_t flags);

LLUV_INTERNAL lluv_handle_t* lluv_chek_handle(lua_State *L, int idx, lluv_flags_t flags);

#endif
