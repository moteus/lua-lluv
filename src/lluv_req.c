/******************************************************************************
* Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
*
* Copyright (C) 2014 Alexey Melnichuk <alexeymelnichuck@gmail.com>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#include "lluv.h"
#include "lluv_req.h"
#include <assert.h>


LLUV_INTERNAL lluv_req_t* lluv_req_new(lua_State *L, uv_req_type type, lluv_handle_t *h){
  size_t extra_size = uv_req_size(type) - sizeof(uv_req_t);
  lluv_req_t *req = (lluv_req_t*)lluv_alloc(L, sizeof(lluv_req_t) + extra_size);

  req->req.data = req;
  req->handle   = h;
  req->cb       = luaL_ref(L, LLUV_LUA_REGISTRY);
  req->arg      = LUA_NOREF;
  return req;
}

LLUV_INTERNAL void lluv_req_free(lua_State *L, lluv_req_t *req){
  luaL_unref(L, LLUV_LUA_REGISTRY, req->cb);
  luaL_unref(L, LLUV_LUA_REGISTRY, req->arg);
  lluv_free(L, req);
}

LLUV_INTERNAL lluv_req_t* lluv_req_byptr(uv_req_t *r){
  size_t off = offsetof(lluv_req_t, req);
  lluv_req_t *req = (lluv_req_t *)(((char*)r) - off);
  assert(req == r->data);
  return req;
}

LLUV_INTERNAL void lluv_req_ref(lua_State *L, lluv_req_t *req){
  luaL_unref(L, LLUV_LUA_REGISTRY, req->arg);
  req->arg = luaL_ref(L, LLUV_LUA_REGISTRY);
}
