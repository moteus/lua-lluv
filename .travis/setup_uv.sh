#! /bin/bash

source .travis/platform.sh

cd $TRAVIS_BUILD_DIR

git clone https://github.com/libuv/libuv.git -b v1.34.2

cd libuv

mkdir -p lib
mkdir -p build
git clone https://chromium.googlesource.com/external/gyp build/gyp

if [ "$PLATFORM" == "macosx" ]; then
  ./gyp_uv.py -f xcode && xcodebuild -ARCHS="x86_64" -project uv.xcodeproj -configuration Release -target All
  cp ./build/Release/libuv.a ./lib;
else
  ./gyp_uv.py -f make && BUILDTYPE=Release CFLAGS=-fPIC make -C out
  cp ./out/Release/libuv.a ./lib;
fi

cd $TRAVIS_BUILD_DIR
