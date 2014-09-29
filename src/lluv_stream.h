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

LLUV_INTERNAL uv_handle_t* lluv_stream_create(lua_State *L, uv_handle_type type);

#endif
