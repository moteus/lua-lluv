#! /bin/bash

source .travis/platform.sh

cd $TRAVIS_BUILD_DIR

git clone https://github.com/joyent/libuv.git

cd libuv

./gyp_uv.py -f make && BUILDTYPE=Release CFLAGS=-fPIC ${MAKE} -C out

cd $TRAVIS_BUILD_DIR
