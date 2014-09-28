/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_UTILS_H_
#define _LLUV_UTILS_H_

#include <uv.h>
#include <lua.h>
#include "l52util.h"

#define LLUV_LUA_REGISTRY lua_upvalueindex(1)
#define LLUV_LOOP_INDEX   lua_upvalueindex(2)

#define LLUV_FLAG_OPEN         (lluv_flags_t)1 << 0

#define LLUV_FLAG_DONT_DESTROY (lluv_flags_t)1 << 1

extern const char *LLUV_MEMORY_ERROR_MARK;

LLUV_INTERNAL void* lluv_alloc(lua_State* L, size_t size);

LLUV_INTERNAL void lluv_free(lua_State* L, void *ptr);

#define lluv_alloc_t(L, T) (T*)lluv_alloc(L, sizeof(T))

#define lluv_free_t(L, T, ptr) lluv_free(L, ptr)

LLUV_INTERNAL int lluv_lua_call(lua_State* L, int narg, int nret);

LLUV_INTERNAL int lluv__index(lua_State *L, const char *meta, lua_CFunction inherit);

LLUV_INTERNAL void lluv_check_callable(lua_State *L, int idx);

LLUV_INTERNAL void lluv_check_none(lua_State *L, int idx);

typedef unsigned char lluv_flag_t;

#define lluv_flags_t unsigned char

#define LLUV_FLAG_0  (lluv_flags_t)1<<0
#define LLUV_FLAG_1  (lluv_flags_t)1<<1
#define LLUV_FLAG_2  (lluv_flags_t)1<<2
#define LLUV_FLAG_3  (lluv_flags_t)1<<3
#define LLUV_FLAG_4  (lluv_flags_t)1<<3

/*At least one flag*/
#define FLAG_IS_SET(O, F) (O->flags & (lluv_flags_t)(F))
/*All flags set*/
#define FLAGS_IS_SET(O, F) ((lluv_flags_t)(F) == (O->flags & (lluv_flags_t)(F)))

#define FLAG_SET(O, F)    O->flags |= (lluv_flags_t)(F)
#define FLAG_UNSET(O, F)  O->flags &= ~((lluv_flags_t)(F))

#endif
