/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_TIMER_H_
#define _LLUV_TIMER_H_

LLUV_INTERNAL void lluv_timer_initlib(lua_State *L, int nup, int safe);

LLUV_INTERNAL int lluv_timer_index(lua_State *L);

#endif
