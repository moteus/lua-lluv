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

#define LLUV_LUA_REGISTRY        lua_upvalueindex(1)
#define LLUV_LOOP_INDEX          lua_upvalueindex(2)
#define LLUV_ERROR_HANDLER_INDEX lua_upvalueindex(3)
#define LLUV_ERROR_MARK_INDEX    lua_upvalueindex(4)

extern const char *LLUV_MEMORY_ERROR_MARK;

LLUV_INTERNAL void* lluv_alloc(lua_State* L, size_t size);

LLUV_INTERNAL void lluv_free(lua_State* L, void *ptr);

#define lluv_alloc_t(L, T) (T*)lluv_alloc(L, sizeof(T))

#define lluv_free_t(L, T, ptr) lluv_free(L, ptr)

LLUV_INTERNAL int lluv_lua_call(lua_State* L, int narg, int nret);

LLUV_INTERNAL int lluv__index(lua_State *L, const char *meta, lua_CFunction inherit);

LLUV_INTERNAL void lluv_check_callable(lua_State *L, int idx);

LLUV_INTERNAL void lluv_check_none(lua_State *L, int idx);

/*
 Check if last argument is callback 
 and maximum number of arguments
*/
LLUV_INTERNAL void lluv_check_args_with_cb(lua_State *L, int n);

LLUV_INTERNAL void lluv_alloc_buffer_cb(uv_handle_t* handle, size_t suggested_size, uv_buf_t *buf);

LLUV_INTERNAL void lluv_free_buffer(uv_handle_t* handle, const uv_buf_t *buf);

LLUV_INTERNAL int lluv_to_addr(lua_State *L, const char *addr, int port, struct sockaddr_storage *sa);

LLUV_INTERNAL int lluv_push_addr(lua_State *L, const struct sockaddr_storage *addr);

LLUV_INTERNAL void lluv_stack_dump(lua_State* L, int top, const char* name);

LLUV_INTERNAL void lluv_value_dump(lua_State* L, int i, const char* prefix);

#define LLUV_IMPLEMENT_XXX_REQ(R, M)                                              \
                                                                                  \
typedef struct lluv_##R##_tag{                                                    \
  uv_##R##_t  req;                                                                \
  lluv_handle_t *handle;                                                          \
  int           cb;                                                               \
}lluv_##R##_t;                                                                    \
                                                                                  \
M lluv_##R##_t *lluv_##R##_new(lua_State *L, lluv_handle_t *h){                   \
  lluv_##R##_t *req = lluv_alloc_t(L, lluv_##R##_t);                              \
  assert(L == h->L);                                                              \
  req->req.data = req;                                                            \
  req->handle   = h;                                                              \
  req->cb       = luaL_ref(L, LLUV_LUA_REGISTRY);                                 \
  return req;                                                                     \
}                                                                                 \
                                                                                  \
M void lluv_##R##_free(lua_State *L, lluv_##R##_t *req){                          \
  if(req->cb != LUA_NOREF)                                                        \
  luaL_unref(L, LLUV_LUA_REGISTRY, req->cb);                                      \
  lluv_free_t(L, lluv_##R##_t, req);                                              \
}                                                                                 \

typedef unsigned char lluv_flag_t;

#define lluv_flags_t unsigned char

#define LLUV_FLAG_0  (lluv_flags_t)1<<0
#define LLUV_FLAG_1  (lluv_flags_t)1<<1
#define LLUV_FLAG_2  (lluv_flags_t)1<<2
#define LLUV_FLAG_3  (lluv_flags_t)1<<3
#define LLUV_FLAG_4  (lluv_flags_t)1<<4
#define LLUV_FLAG_5  (lluv_flags_t)1<<5
#define LLUV_FLAG_6  (lluv_flags_t)1<<6
#define LLUV_FLAG_7  (lluv_flags_t)1<<7

/*At least one flag*/
#define FLAG_IS_SET(O, F) (O->flags & (lluv_flags_t)(F))
/*All flags set*/
#define FLAGS_IS_SET(O, F) ((lluv_flags_t)(F) == (O->flags & (lluv_flags_t)(F)))

#define FLAG_SET(O, F)    O->flags |= (lluv_flags_t)(F)
#define FLAG_UNSET(O, F)  O->flags &= ~((lluv_flags_t)(F))

#define IS_(O, F)    FLAG_IS_SET(O, LLUV_FLAG_##F)
#define SET_(O, F)   FLAG_SET(O,    LLUV_FLAG_##F)
#define UNSET_(O, F) FLAG_UNSET(O,  LLUV_FLAG_##F)

#define IS(O, F)     FLAG_IS_SET(O, F)
#define SET(O, F)    FLAG_SET(O, F)
#define UNSET(O, F)  FLAG_UNSET(O, F)

#define LLUV_FLAG_OPEN         LLUV_FLAG_0
#define LLUV_FLAG_STREAM       LLUV_FLAG_1
#define LLUV_FLAG_DEFAULT_LOOP LLUV_FLAG_1
#define LLUV_FLAG_RAISE_ERROR  LLUV_FLAG_2
#define LLUV_FLAG_BUFFER_BUSY  LLUV_FLAG_3

#define INHERITE_FLAGS(O) (O->flags & (LLUV_FLAG_RAISE_ERROR))


#define UNUSED_ARG(arg) (void)arg

#endif
