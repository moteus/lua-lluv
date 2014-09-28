/******************************************************************************
* Author: Alexey Melnichuk <mimir@newmail.ru>
*
* Copyright (C) 2014 Alexey Melnichuk <mimir@newmail.ru>
*
* Licensed according to the included 'LICENSE' document
*
* This file is part of lua-lluv library.
******************************************************************************/

#include "lluv_fs.h"
#include "lluv_error.h"
#include "lluv_loop.h"
#include "lluv_fbuf.h"
#include <assert.h>
#include <fcntl.h>

/* callback signatures  callback(loop|file, err|nil, ...)
** one exaption is fs_open callback(file|nil, err|nil, path)
**
**/

typedef struct lluv_fs_request_tag{
  uv_fs_t req;
  lua_State *L;
  int cb;
  int file_ref;
}lluv_fs_request_t;

lluv_fs_request_t *lluv_fs_request_new(lua_State *L){
  lluv_fs_request_t *req = lluv_alloc_t(L, lluv_fs_request_t);
  req->L        = L;
  req->req.data = req;
  req->cb = req->file_ref = LUA_NOREF;
  return req;
}

void lluv_fs_request_free(lua_State *L, lluv_fs_request_t *req){
  if(req->cb != LUA_NOREF)
    luaL_unref(L, LLUV_LUA_REGISTRY, req->cb);
  if(req->file_ref != LUA_NOREF)
    luaL_unref(L, LLUV_LUA_REGISTRY, req->file_ref);
  lluv_free_t(L, lluv_fs_request_t, req);
}

#ifdef _WIN32
 #ifndef S_ISDIR
   #define S_ISDIR(mode)  (mode&_S_IFDIR)
 #endif
 #ifndef S_ISREG
   #define S_ISREG(mode)  (mode&_S_IFREG)
 #endif
 #ifndef S_ISLNK
   #define S_ISLNK(mode)  (0)
 #endif
 #ifndef S_ISSOCK
   #define S_ISSOCK(mode)  (0)
 #endif
 #ifndef S_ISFIFO
   #define S_ISFIFO(mode)  (0)
 #endif
 #ifndef S_ISCHR
   #define S_ISCHR(mode)  (mode&_S_IFCHR)
 #endif
 #ifndef S_ISBLK
   #define S_ISBLK(mode)  (0)
 #endif
#endif

#ifndef O_SYNC
  #define O_SYNC 0
#endif

static void lluv_push_stats_table(lua_State* L, uv_stat_t* s) {
#define SET_FIELD_INT(F,V)  lutil_pushint64(L, s->V);         lua_setfield(L, -2, F)
#define SET_FIELD_MODE(F,V) lua_pushboolean(L, V(s->st_mode));lua_setfield(L, -2, F)
//! @todo push full time (not only seconds)
#define SET_FIELD_TIME(F,V) lutil_pushint64(L, s->V.tv_sec);  lua_setfield(L, -2, F)

  lua_newtable(L);
  SET_FIELD_INT( "dev"    , st_dev    );
  SET_FIELD_INT( "ino"    , st_ino    );
  SET_FIELD_INT( "mode"   , st_mode   );
  SET_FIELD_INT( "nlink"  , st_nlink  );
  SET_FIELD_INT( "uid"    , st_uid    );
  SET_FIELD_INT( "gid"    , st_gid    );
  SET_FIELD_INT( "rdev"   , st_rdev   );
  SET_FIELD_INT( "size"   , st_size   );
  SET_FIELD_INT( "blksize", st_blksize);
  SET_FIELD_INT( "blocks" , st_blocks );

  SET_FIELD_MODE("is_file"             , S_ISREG  );
  SET_FIELD_MODE("is_directory"        , S_ISDIR  );
  SET_FIELD_MODE("is_character_device" , S_ISCHR  );
  SET_FIELD_MODE("is_block_device"     , S_ISBLK  );
  SET_FIELD_MODE("is_fifo"             , S_ISFIFO );
  SET_FIELD_MODE("is_symbolic_link"    , S_ISLNK  );
  SET_FIELD_MODE("is_socket"           , S_ISSOCK );

  SET_FIELD_TIME("atime", st_atim );
  SET_FIELD_TIME("mtime", st_mtim );
  SET_FIELD_TIME("ctime", st_ctim );

#undef SET_FIELD_INT
#undef SET_FIELD_MODE
#undef SET_FIELD_TIME
}

static int lluv_file_create(lua_State *L, lluv_loop_t  *loop, uv_file h, unsigned char flags);

static int lluv_push_fs_result_object(lua_State* L, lluv_fs_request_t* lreq) {
  uv_fs_t *req = &lreq->req;
  lluv_loop_t *loop = req->loop->data;

  switch (req->fs_type) {
    case UV_FS_RENAME:
    case UV_FS_UNLINK:
    case UV_FS_RMDIR:
    case UV_FS_MKDIR:
    case UV_FS_MKDTEMP:
    case UV_FS_UTIME:
    case UV_FS_CHMOD:
    case UV_FS_LINK:
    case UV_FS_SYMLINK:
    case UV_FS_CHOWN:
    case UV_FS_READLINK:
    case UV_FS_READDIR:
    case UV_FS_STAT:
    case UV_FS_LSTAT:
      lua_pushvalue(L, LLUV_LOOP_INDEX);
      return 1;

    case UV_FS_OPEN:
      if(req->result < 0) lua_pushnil(L);
      else lluv_file_create(L, loop, (uv_file)req->result, 0);
      return 1;

    case UV_FS_CLOSE:
    case UV_FS_FTRUNCATE:
    case UV_FS_FSYNC:
    case UV_FS_FDATASYNC:
    case UV_FS_FUTIME:
    case UV_FS_FCHMOD:
    case UV_FS_FCHOWN:
    case UV_FS_FSTAT:
    case UV_FS_WRITE:
    case UV_FS_READ:
      lua_rawgeti(L, LLUV_LUA_REGISTRY, lreq->file_ref);
      return 1;

    case UV_FS_SENDFILE:
      lua_rawgeti(L, LLUV_LUA_REGISTRY, lreq->file_ref);
      return 1;

    default:
      fprintf(stderr, "UNKNOWN FS TYPE %d\n", req->fs_type);
      return 0;
  }
}

static int lluv_push_fs_result(lua_State* L, lluv_fs_request_t* lreq) {
  uv_fs_t *req = &lreq->req;
  lluv_loop_t *loop = req->loop->data;

  switch (req->fs_type) {
    case UV_FS_RENAME:
    case UV_FS_UNLINK:
    case UV_FS_RMDIR:
    case UV_FS_MKDIR:
    case UV_FS_MKDTEMP:
    case UV_FS_UTIME:
    case UV_FS_CHMOD:
    case UV_FS_LINK:
    case UV_FS_SYMLINK:
    case UV_FS_CHOWN:
      lua_pushstring(L, req->path);
      return 1;

    case UV_FS_CLOSE:
    case UV_FS_FTRUNCATE:
    case UV_FS_FSYNC:
    case UV_FS_FDATASYNC:
    case UV_FS_FUTIME:
    case UV_FS_FCHMOD:
    case UV_FS_FCHOWN:
    case UV_FS_OPEN:
      if(req->path) lua_pushstring(L, req->path);
      else lua_pushboolean(L, 1);
      return 1;

    case UV_FS_SENDFILE:
      lutil_pushint64(L, req->result);
      return 1;

    case UV_FS_STAT:
    case UV_FS_LSTAT:
      lua_pushstring(L, req->path);
      lluv_push_stats_table(L, &req->statbuf);
      return 2;
    case UV_FS_FSTAT:
      lluv_push_stats_table(L, &req->statbuf);
      return 1;

    case UV_FS_READLINK:
      lua_pushstring(L, (char*)req->ptr);
      return 1;

    case UV_FS_WRITE:
    case UV_FS_READ:
      lua_rawgetp(L, LLUV_LUA_REGISTRY, req);
      lua_pushnil(L); lua_rawsetp(L, LLUV_LUA_REGISTRY, req);
      lutil_pushint64(L, req->result);
      return 2;

    case UV_FS_READDIR:{
      uv_dirent_t ent;
      int i = 0, err;
      lua_createtable(L, (int)req->result, 0);
      while((err = uv_fs_readdir_next(req, &ent)) >= 0){
        lua_createtable(L, 2, 0);
          lua_pushstring (L, ent.name); lua_rawseti(L, -2, 1);
          lutil_pushint64(L, ent.type); lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, ++i);
      }
      return 1;
    }

    default:
      fprintf(stderr, "UNKNOWN FS TYPE %d\n", req->fs_type);
      return 0;
  }
}

static void lluv_on_fs(uv_fs_t *arg){
  lluv_fs_request_t *req = arg->data;
  lua_State *L = req->L;
  int argc, top = lua_gettop(L);

  lua_rawgeti(L, LLUV_LUA_REGISTRY, req->cb);

  argc = lluv_push_fs_result_object(L, req);

  if(arg->result < 0){
    lluv_error_create(L, LLUV_ERR_UV, arg->result, arg->path);
    ++argc;
  }
  else{
    lua_pushnil(L);
    argc += 1 + lluv_push_fs_result(L, req);
  }
  uv_fs_req_cleanup(&req->req);
  lluv_fs_request_free(L, req);

  lluv_lua_call(L, argc, 0);
  lua_settop(L, top);
}

//{ Macro
#define LLUV_CHECK_LOOP_FS()                                           \
  lluv_loop_t *loop  = lluv_opt_loop(L, 1, LLUV_FLAG_OPEN);            \
  int argc = loop? 1 : 0;                                              \

#define LLUV_PRE_FS(){                                                 \
  lluv_fs_request_t *req = lluv_fs_request_new(L);                     \
  int err;  uv_fs_cb cb = NULL;                                        \
                                                                       \
  if(!loop)loop = lluv_default_loop(L);                                \
                                                                       \
  if(lua_gettop(L) > argc){                                            \
    lua_settop(L, argc + 1);                                           \
    cb = lluv_on_fs;                                                   \
  }                                                                    \

#define LLUV_POST_FS()                                                 \
  if(err < 0){                                                         \
    lluv_error_create(L, LLUV_ERR_UV, err, path);                      \
    lluv_fs_request_free(L, req);                                      \
    if(cb){                                                            \
      lua_pcall(L, 1, 0, 0);                                           \
      return 0;                                                        \
    }                                                                  \
    lua_pushnil(L);                                                    \
    lua_insert(L, -2);                                                 \
    return 2;                                                          \
  }                                                                    \
                                                                       \
  if(cb){                                                              \
    req->cb = luaL_ref(L, LLUV_LUA_REGISTRY);                          \
    return 0;                                                          \
  }                                                                    \
                                                                       \
  if(req->req.result < 0){                                             \
    lua_pushnil(L);                                                    \
    lluv_error_create(L, LLUV_ERR_UV, req->req.result, req->req.path); \
    argc = 2;                                                          \
  }                                                                    \
  else{                                                                \
    if(req->req.fs_type == UV_FS_OPEN){                                \
      lluv_file_create(L, loop, (uv_file)req->req.result, 0);          \
      argc = 1;                                                        \
    }                                                                  \
    else argc = 0;                                                     \
    argc += lluv_push_fs_result(L, req);                               \
  }                                                                    \
                                                                       \
  uv_fs_req_cleanup(&req->req);                                        \
  lluv_fs_request_free(L, req);                                        \
                                                                       \
  return argc;                                                         \
}

#define lluv_arg_exists(L, idx) ((!lua_isnone(L, idx)) && (lua_type(L, idx) != LUA_TFUNCTION))

//}

//{ FS operations

static int lluv_fs_unlink(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_unlink(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_mkdtemp(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = "./XXXXXX";
  if(lluv_arg_exists(L, argc + 1)){
    path = luaL_checkstring(L, ++argc);
  }

  LLUV_PRE_FS();
  err = uv_fs_mkdtemp(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_mkdir(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path   = luaL_checkstring(L, ++argc);
  int mode = 0;
  if(lluv_arg_exists(L, argc + 1)){
    mode = (int)luaL_checkinteger(L, ++argc);
  }

  LLUV_PRE_FS();
  err = uv_fs_mkdir(loop->handle, &req->req, path, mode, cb);
  LLUV_POST_FS();
}

static int lluv_fs_rmdir(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_rmdir(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_readdir(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);
  int flags = 0;
  if(lluv_arg_exists(L, argc + 1)){
    flags = (int)luaL_checkinteger(L, ++argc);
  }

  LLUV_PRE_FS();
  err = uv_fs_readdir(loop->handle, &req->req, path, flags, cb);
  LLUV_POST_FS();
}

static int lluv_fs_stat(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_stat(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_lstat(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_lstat(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_rename(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path     = luaL_checkstring(L, ++argc);
  const char *new_path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_rename(loop->handle, &req->req, path, new_path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_chmod(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring (L, ++argc);
  int         mode = (int)luaL_checkinteger(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_chmod(loop->handle, &req->req, path, mode, cb);
  LLUV_POST_FS();
}

static int lluv_fs_utime(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);
  double     atime = luaL_checknumber(L, ++argc);
  double     mtime = luaL_checknumber(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_utime(loop->handle, &req->req, path, atime, mtime, cb);
  LLUV_POST_FS();
}

static int lluv_fs_symlink(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path     = luaL_checkstring(L, ++argc);
  const char *new_path = luaL_checkstring(L, ++argc);
  int flags = 0;
  if(lluv_arg_exists(L, 3)){
    flags = (int)luaL_checkinteger(L, ++argc);
  }

  LLUV_PRE_FS();
  err = uv_fs_symlink(loop->handle, &req->req, path, new_path, flags, cb);
  LLUV_POST_FS();
}

static int lluv_fs_readlink(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_readlink(loop->handle, &req->req, path, cb);
  LLUV_POST_FS();
}

static int lluv_fs_chown(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);
  uv_uid_t     uid = (uv_uid_t)lutil_checkint64(L, ++argc);
  uv_gid_t     gid = (uv_gid_t)lutil_checkint64(L, ++argc);

  LLUV_PRE_FS();
  err = uv_fs_chown(loop->handle, &req->req, path, uid, gid, cb);
  LLUV_POST_FS();
}

static int luv_check_open_flags(lua_State *L, int idx, const char *def){
  static const char *names[] = {
    "r"  ,
    "rs" ,
    "sr" ,
    "r+" ,
    "rs+",
    "sr+",
    "w"  ,
    "wx" ,
    "xw" ,
    "w+" ,
    "wx+",
    "xw+",
    "a"  ,
    "ax" ,
    "xa" ,
    "a+" ,
    "ax+",
    "xa+",
    NULL,
  };

  static const int flags[] = {
    O_RDONLY                               ,/*  r    */
    O_RDONLY | O_SYNC                      ,/*  rs   */
    O_RDONLY | O_SYNC                      ,/*  sr   */
    O_RDWR                                 ,/*  r+   */
    O_RDWR   | O_SYNC                      ,/*  rs+  */
    O_RDWR   | O_SYNC                      ,/*  sr+  */
    O_TRUNC  | O_CREAT | O_WRONLY          ,/*  w    */
    O_TRUNC  | O_CREAT | O_WRONLY | O_EXCL ,/*  wx   */
    O_TRUNC  | O_CREAT | O_WRONLY | O_EXCL ,/*  xw   */
    O_TRUNC  | O_CREAT | O_RDWR            ,/*  w+   */
    O_TRUNC  | O_CREAT | O_RDWR   | O_EXCL ,/*  wx+  */
    O_TRUNC  | O_CREAT | O_RDWR   | O_EXCL ,/*  xw+  */
    O_APPEND | O_CREAT | O_WRONLY          ,/*  a    */
    O_APPEND | O_CREAT | O_WRONLY | O_EXCL ,/*  ax   */
    O_APPEND | O_CREAT | O_WRONLY | O_EXCL ,/*  xa   */
    O_APPEND | O_CREAT | O_RDWR            ,/*  a+   */
    O_APPEND | O_CREAT | O_RDWR   | O_EXCL ,/*  ax+  */
    O_APPEND | O_CREAT | O_RDWR   | O_EXCL ,/*  xa+  */
  };

  //! @todo static assert before change names/flags
  
  int flag = luaL_checkoption(L, idx, def, names);

  return flags[flag];
}

static int lluv_fs_open(lua_State* L) {
  LLUV_CHECK_LOOP_FS()

  const char *path = luaL_checkstring(L, ++argc);
  int        flags = luv_check_open_flags(L, ++argc, NULL);
  int         mode = 0666;

  if(lluv_arg_exists(L, argc+1)){
    mode = (int)luaL_checkinteger(L, ++argc);
  }

  LLUV_PRE_FS();
  err = uv_fs_open(loop->handle, &req->req, path, flags, mode, cb);
  LLUV_POST_FS();
}

//}

//{ File object

#define LLUV_FILE_NAME LLUV_PREFIX" File"
static const char *LLUV_FILE = LLUV_FILE_NAME;

typedef struct lluv_file_tag{
  uv_file      handle;
  lluv_flags_t flags;
  lluv_loop_t  *loop;
}lluv_file_t;

static int lluv_file_create(lua_State *L, lluv_loop_t  *loop, uv_file h, unsigned char flags){
  lluv_file_t *f = lutil_newudatap(L, lluv_file_t, LLUV_FILE);
  f->handle = h;
  f->loop   = loop;
  f->flags  = flags | LLUV_FLAG_OPEN; 
  return 1;
}

static lluv_file_t *lluv_check_file(lua_State *L, int i, lluv_flags_t flags){
  lluv_file_t *f = (lluv_file_t *)lutil_checkudatap (L, i, LLUV_FILE);
  luaL_argcheck (L, f != NULL, i, LLUV_FILE_NAME" expected");

  luaL_argcheck (L, FLAGS_IS_SET(f, flags), i, LLUV_FILE_NAME" closed");

  return f;
}

static int lluv_file_to_s(lua_State *L){
  lluv_file_t *f = lluv_check_file(L, 1, 0);
  lua_pushfstring(L, LLUV_FILE_NAME" (%p)", f);
  return 1;
}

static int lluv_file_close(lua_State *L){
  lluv_file_t *f = lluv_check_file(L, 1, 0);
  lluv_loop_t *loop = f->loop;

  if(f->flags | LLUV_FLAG_OPEN){
    const char  *path = NULL;
    int          argc = 1;
    f->flags &= ~LLUV_FLAG_OPEN;

    LLUV_PRE_FS();
    err = uv_fs_close(loop->handle, &req->req, f->handle, cb);
    LLUV_POST_FS();
  }

  return 0;
}

static int lluv_file_loop(lua_State *L){
  lluv_file_t *f = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lua_rawgetp(L, LLUV_LUA_REGISTRY, f->loop->handle);
  return 1;
}

static int lluv_file_stat(lua_State *L){
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  int          argc = 1;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_fstat(loop->handle, &req->req, f->handle, cb);
  LLUV_POST_FS();
}

static int lluv_file_sync(lua_State *L){
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  int          argc = 1;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_fsync(loop->handle, &req->req, f->handle, cb);
  LLUV_POST_FS();
}

static int lluv_file_datasync(lua_State *L){
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  int          argc = 1;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_fdatasync(loop->handle, &req->req, f->handle, cb);
  LLUV_POST_FS();
}

static int lluv_file_truncate(lua_State *L){
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  int64_t      len  = lutil_checkint64(L, 2);
  int         argc  = 2;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_ftruncate(loop->handle, &req->req, f->handle, len, cb);
  LLUV_POST_FS();
}

static int lluv_file_chown(lua_State* L) {
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  uv_uid_t     uid  = (uv_uid_t)lutil_checkint64(L, 2);
  uv_gid_t     gid  = (uv_gid_t)lutil_checkint64(L, 3);
  int         argc  = 3;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_fchown(loop->handle, &req->req, f->handle, uid, gid, cb);
  LLUV_POST_FS();
}

static int lluv_file_chmod(lua_State* L) {
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  int         mode  = (int)luaL_checkinteger(L, 2);
  int         argc  = 2;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_fchmod(loop->handle, &req->req, f->handle, mode, cb);
  LLUV_POST_FS();
}

static int lluv_file_utime(lua_State* L) {
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;
  double     atime  = luaL_checknumber(L, 2);
  double     mtime  = luaL_checknumber(L, 3);
  int         argc  = 3;

  LLUV_PRE_FS();
  lua_pushvalue(L, 1);
  req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
  err = uv_fs_futime(loop->handle, &req->req, f->handle, atime, mtime, cb);
  LLUV_POST_FS();
}

static int lluv_file_readb(lua_State* L) {
  const char  *path = NULL;
  lluv_file_t *f    = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop = f->loop;

  char *base; size_t capacity;
  lluv_fixed_buffer_t *buffer;

  int64_t   position = 0; /* position in file default: 0*/ 
  int64_t   offset   = 0; /* offset in buffer default: 0*/
  size_t    length   = 0; /* number or bytes  default: buffer->capacity - offset*/

  int         argc = 2;

  if(lua_islightuserdata(L, argc)){
    base     = lua_touserdata(L, argc);
    capacity = (size_t)lutil_checkint64(L, ++argc);
  }
  else{
    buffer   = lluv_check_fbuf(L, argc);
    base     = buffer->data;
    capacity = buffer->capacity;
  }

  if(lluv_arg_exists(L, argc+1)){      /* position        */
    position = lutil_checkint64(L, ++argc);
  }
  if(lluv_arg_exists(L, argc+2)){      /* offset + length */
    offset = lutil_checkint64(L, ++argc);
    length = (size_t)lutil_checkint64(L, ++argc);
  }
  else if(lluv_arg_exists(L, argc+1)){ /* offset          */
    offset = lutil_checkint64(L, ++argc);
    length = capacity - offset;
  }
  else{
    length = capacity;
  }

  luaL_argcheck (L, capacity > (size_t)offset, 4, LLUV_PREFIX" offset out of index"); 
  luaL_argcheck (L, capacity >= ((size_t)offset + length), 5, LLUV_PREFIX" length out of index");

  LLUV_PRE_FS();
  {
    uv_buf_t ubuf = uv_buf_init(&base[offset], length);

    lua_pushvalue(L, 2);
    lua_rawsetp(L, LLUV_LUA_REGISTRY, &req->req);
    lua_pushvalue(L, 1);
    req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
    err = uv_fs_read(loop->handle, &req->req, f->handle, &ubuf, 1, position, cb);
  }
  LLUV_POST_FS();
}

static int lluv_file_read(lua_State* L) {
  // if buffer_length provided then function allocate buffer with this size
  // read(buffer | buffer_length, [position, [ [offset,] [length,] ] ] [callback])

  if(lua_isnumber(L, 2)){
    int64_t len = lutil_checkint64(L, 2);
    lluv_fbuf_alloc(L, (size_t)len);
    lua_remove(L, 2); // replace length
    lua_insert(L, 2); // with buffer
  }
  return lluv_file_readb(L);
}

static int lluv_file_write(lua_State* L) {
  // if you provide string then function does not copy this string
  // read(buffer | string, [position, [ [offset,] [length,] ] ] [callback])

  const char  *path           = NULL;
  lluv_file_t *f              = lluv_check_file(L, 1, LLUV_FLAG_OPEN);
  lluv_loop_t *loop           = f->loop;
  lluv_fixed_buffer_t *buffer = NULL;
  const char *str             = NULL;
  size_t    capacity;
  int64_t   position          = 0; /* position in file default: 0*/ 
  int64_t   offset            = 0; /* offset in buffer default: 0*/
  size_t    length            = 0; /* number or bytes  default: buffer->capacity - offset*/
  
  int         argc = 2;

  if(NULL == (str = lua_tolstring(L, 2, &capacity))){
    buffer   = lluv_check_fbuf(L, 2);
    capacity = buffer->capacity;
    str      = buffer->data;
  }

  if(lluv_arg_exists(L, 3)){      /* position        */
    position = lutil_checkint64(L, ++argc);
  }
  if(lluv_arg_exists(L, 5)){      /* offset + length */
    offset = lutil_checkint64(L, ++argc);
    length = (size_t)lutil_checkint64(L, ++argc);
  }
  else if(lluv_arg_exists(L, 4)){ /* offset          */
    offset = lutil_checkint64(L, ++argc);
    length = capacity - offset;
  }
  else{
    length = capacity;
  }

  luaL_argcheck (L, capacity > (size_t)offset, 4, LLUV_PREFIX" offset out of index"); 
  luaL_argcheck (L, capacity >= ((size_t)offset + length), 5, LLUV_PREFIX" length out of index");

  LLUV_PRE_FS();
  {
    uv_buf_t ubuf = uv_buf_init((char*)&str[offset], length);
    
    lua_pushvalue(L, 2); /*string or buffer*/
    lua_rawsetp(L, LLUV_LUA_REGISTRY, &req->req);
    lua_pushvalue(L, 1);
    req->file_ref = luaL_ref(L, LLUV_LUA_REGISTRY);
    err = uv_fs_write(loop->handle, &req->req, f->handle, &ubuf, 1, position, cb);
  }
  LLUV_POST_FS();
}

static const struct luaL_Reg lluv_file_methods[] = {
  {"loop",         lluv_file_loop      },
  {"stat",         lluv_file_stat      },
  {"sync",         lluv_file_sync      },
  {"datasync",     lluv_file_datasync  },
  {"truncate",     lluv_file_truncate  },
  {"close",        lluv_file_close     },
  {"chown",        lluv_file_chown     },
  {"chmod",        lluv_file_chmod     },
  {"utime",        lluv_file_utime     },

  {"read",         lluv_file_read      },
  {"write",        lluv_file_write     },
  {"__gc",         lluv_file_close     },
  {"__tostring",   lluv_file_to_s      },
  
  {NULL,NULL}
};

//}

static const struct luaL_Reg lluv_fs_functions[] = {
  { "fs_unlink",   lluv_fs_unlink   },
  { "fs_mkdtemp",  lluv_fs_mkdtemp  },
  { "fs_mkdir",    lluv_fs_mkdir    },
  { "fs_rmdir",    lluv_fs_rmdir    },
  { "fs_readdir",  lluv_fs_readdir  },
  { "fs_stat",     lluv_fs_stat     },
  { "fs_lstat",    lluv_fs_lstat    },
  { "fs_rename",   lluv_fs_rename   },
  { "fs_chmod",    lluv_fs_chmod    },
  { "fs_utime",    lluv_fs_utime    },
  { "fs_symlink",  lluv_fs_symlink  },
  { "fs_readlink", lluv_fs_readlink },
  { "fs_chown",    lluv_fs_chown    },

  { "fs_open",     lluv_fs_open     },

  {NULL,NULL}
};

LLUV_INTERNAL void lluv_fs_initlib(lua_State *L, int nup){
  lutil_pushnvalues(L, nup);

  if(!lutil_createmetap(L, LLUV_FILE, lluv_file_methods, nup))
    lua_pop(L, nup);
  lua_pop(L, 1);

  luaL_setfuncs(L, lluv_fs_functions, nup);
}
