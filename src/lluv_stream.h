/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_STREAM_H_
#define _LLUV_STREAM_H_

LLUV_INTERNAL void lluv_stream_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_stream_index(lua_State *L);

LLUV_INTERNAL uv_handle_t* lluv_stream_create(lua_State *L, uv_handle_type type, lluv_flags_t flags);

LLUV_INTERNAL lluv_handle_t* lluv_check_stream(lua_State *L, int idx, lluv_flags_t flags);

LLUV_INTERNAL void lluv_on_stream_connect_cb(uv_connect_t* arg, int status);

typedef struct lluv_connect_tag lluv_connect_t;

LLUV_INTERNAL lluv_connect_t *lluv_connect_new(lua_State *L, lluv_handle_t *h);

LLUV_INTERNAL void lluv_connect_free(lua_State *L, lluv_connect_t *req);

#endif
