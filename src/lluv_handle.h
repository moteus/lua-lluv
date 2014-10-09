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

#define LLUV_CLOSE_CB(H)      H->callbacks[0]
#define LLUV_START_CB(H)      H->callbacks[1]
#define LLUV_READ_CB(H)       H->callbacks[1]
#define LLUV_EXIT_CB(H)       H->callbacks[1]
#define LLUV_CONNECTION_CB(H) H->callbacks[2]
#define LLUV_MAX_HANDLE_CB    3


#include "lluv.h"
#include "lluv_utils.h"

typedef struct lluv_handle_tag{
  int         self;
  lua_State   *L;
  lluv_flags_t flags;
  int          ud_ref; /* userdata reference */
  int          callbacks[LLUV_MAX_HANDLE_CB];
  uv_handle_t  handle;
} lluv_handle_t;

//! @todo make debug verions with check cast with checking uv_handle_type
#define LLUV_H(H, T) ((T*)&H->handle)

LLUV_INTERNAL void lluv_handle_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_handle_index(lua_State *L);

LLUV_INTERNAL lluv_handle_t* lluv_handle_create(lua_State *L, uv_handle_type type, lluv_flags_t flags);

LLUV_INTERNAL lluv_handle_t* lluv_check_handle(lua_State *L, int idx, lluv_flags_t flags);

LLUV_INTERNAL void lluv_handle_cleanup(lua_State *L, lluv_handle_t *handle);

LLUV_INTERNAL lluv_handle_t* lluv_handle_byptr(uv_handle_t *h);

LLUV_INTERNAL int lluv_handle_push(lua_State *L, uv_handle_t *h);

LLUV_INTERNAL int lluv_handle_pushself(lua_State *L, lluv_handle_t *handle);

LLUV_INTERNAL void lluv_on_handle_start(uv_handle_t *arg);

#endif
