#! /bin/bash

source .travis/platform.sh

cd $TRAVIS_BUILD_DIR

git clone https://github.com/joyent/libuv.git

cd libuv

mkdir -p build
git clone https://git.chromium.org/external/gyp.git build/gyp

./gyp_uv.py -f make && BUILDTYPE=Release CFLAGS=-fPIC make -C out

cd $TRAVIS_BUILD_DIR
