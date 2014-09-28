/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#ifndef _LLUV_ERROR_H_
#define _LLUV_ERROR_H_

#include "lluv.h"

#define LLUV_ERROR_RETURN 1
#define LLUV_ERROR_RAISE  2

/* error category */
#define LLUV_ERR_LIB 0
#define LLUV_ERR_UV  1

typedef struct lluv_error_tag{
  int        cat;
  uv_errno_t no;
  char       ext[1];
}lluv_error_t;

LLUV_INTERNAL void lluv_error_initlib(lua_State *L, int nup);

LLUV_INTERNAL int lluv_error_create(lua_State *L, int error_category, uv_errno_t error_no, const char *ext);

LLUV_INTERNAL int lluv_fail(lua_State *L, int mode, int error_category, uv_errno_t error_no, const char *ext);

#endif


