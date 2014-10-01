/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_FS_POLL_H_
#define _LLUV_FS_POLL_H_

LLUV_INTERNAL void lluv_fs_poll_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_fs_poll_index(lua_State *L);

#endif