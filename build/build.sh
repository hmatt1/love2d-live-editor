#!/usr/bin/env bash
set -euo pipefail

# Pinned commits for reproducible builds
LOVEJS_COMMIT="c4f04e185033a7c9fbefa9be3bec88c41a90421b"
LOVE_COMMIT="32e0716b43a51686f5fa9ac04ca08b6410b698a5"
MEGA_COMMIT="3bc0b46670a2912c02c54c6977b9510e64e89023"

echo "==> Cloning repositories..."
git clone --depth=50 https://github.com/Davidobot/love.js lovejs
cd lovejs && git checkout "$LOVEJS_COMMIT" && cd ..

git clone --depth=50 -b emscripten https://github.com/Davidobot/love love_src
cd love_src && git checkout "$LOVE_COMMIT" && cd ..

git clone --depth=50 -b emscripten https://github.com/Davidobot/megasource megasource
cd megasource && git checkout "$MEGA_COMMIT"
# megasource has no .gitmodules — all deps are committed directly.
# libs/love is supplied via -DMEGA_LOVE at cmake time; no submodule init needed.
cd ..

echo "==> Injecting fetch module..."
cp -r /build/src/modules/fetch love_src/src/modules/fetch

echo "==> Applying patches..."
cd love_src
patch -p1 < /build/patches/CMakeLists.patch
patch -p1 < /build/patches/love_cpp.patch
cd ..

echo "==> Building compat (no pthreads)..."
mkdir -p out_compat && cd out_compat

# megasource is the cmake source; -DMEGA_LOVE points it at our patched love source
emcmake cmake ../megasource \
    -DMEGA_LOVE="$(pwd)/../love_src" \
    -DLOVE_JIT=0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DLOVEJS_COMPAT=1 \
    -DSEXPORT_ALL=1 \
    -DSMAIN_MODULE=1 \
    -DSERROR_ON_UNDEFINED_SYMBOLS=0

emmake make -j"$(nproc)"
cd ..

echo "==> Copying artifacts..."
cp out_compat/love/love.js  /out/love.js
cp out_compat/love/love.wasm /out/love.wasm

echo "==> Done. love.js and love.wasm written to /out/"
