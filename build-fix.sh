#!/bin/bash

# Local build script mirroring the Linux CI recipe in build-release.yaml
set -euo pipefail

echo "Building Frostrig (Linux local build)..."

CFLAGS="-O2 -fPIC"

# ------------------------------------------------------------------
# RandomX variant wrappers
# ------------------------------------------------------------------
echo "Building C modules..."
for f in algo/randomx/0.c algo/randomx/wow.c algo/randomx/2.c \
         algo/randomx/c64.c algo/randomx/v.c algo/randomx/xeq.c \
         algo/keva/keva.c; do
  O="${f%.c}.o"
  echo "  -> ${O}"
  gcc $CFLAGS -c -Ialgo/randomx -Ialgo/keva "${f}" -o "${O}"
done

# BLAKE2b (uses the Argon2-tree blake2b.c)
echo "  -> algo/blake2b/blake2b.o"
gcc $CFLAGS -c -Ithird_party/argon2/include -Ithird_party/argon2/src \
   -Ialgo/blake2b algo/blake2b/blake2b.c -o algo/blake2b/blake2b.o

# CryptoNight (pico + heavy share one translation unit; AES-NI intrinsics need -maes)
echo "  -> algo/cryptonight/cryptonight.o"
gcc $CFLAGS -maes -c -Ithird_party/argon2/include \
   -Ithird_party/argon2/src -Ialgo/cryptonight \
   algo/cryptonight/cryptonight.c -o algo/cryptonight/cryptonight.o

# GhostRider (chameleon hash, uses BLAKE2b from the Argon2 tree)
echo "  -> algo/ghostrider/ghostrider.o"
gcc $CFLAGS -c -Ithird_party/argon2/include -Ithird_party/argon2/src \
   -Ialgo/ghostrider algo/ghostrider/ghostrider.c -o algo/ghostrider/ghostrider.o

# Argon2: combine third_party/argon2/src/*.c + algo/argon2/*.c
rm -f algo/argon2/argon2_all.o algo/verushash/verushash_all.o
echo "  -> algo/argon2/argon2_all.o"
mkdir -p /tmp/argon2_objs
for f in third_party/argon2/src/argon2.c third_party/argon2/src/blake2b.c \
         third_party/argon2/src/core.c third_party/argon2/src/encoding.c \
         third_party/argon2/src/opt.c third_party/argon2/src/thread.c; do
  B=$(basename "${f}" .c)
  gcc -O2 -fPIC -c -Ithird_party/argon2/include -Ithird_party/argon2/src \
     "${f}" -o "/tmp/argon2_objs/${B}.o"
done
gcc -O2 -fPIC -c -Ialgo/argon2 -Ithird_party/argon2/include -Ithird_party/argon2/src \
  algo/argon2/argon2_id.c -o /tmp/argon2_objs/argon2_id.o
gcc -O2 -fPIC -c -Ialgo/argon2 -Ithird_party/argon2/include -Ithird_party/argon2/src \
  algo/argon2/argon2d.c -o /tmp/argon2_objs/argon2d.o
ar rcs algo/argon2/argon2_all.o /tmp/argon2_objs/*.o
rm -rf /tmp/argon2_objs

# VerusHash: C + C++ sources
echo "  -> algo/verushash/verushash_all.o"
mkdir -p /tmp/vh_objs
gcc -O2 -fPIC -c algo/verushash/haraka_portable.c -o /tmp/vh_objs/haraka.o
c++ -O2 -fPIC -std=c++11 -c algo/verushash/verushash.cpp -o /tmp/vh_objs/vh.o
c++ -O2 -fPIC -std=c++11 -c algo/verushash/vh_clhash_portable.cpp -o /tmp/vh_objs/vh_cl.o
c++ -O2 -fPIC -std=c++11 -c algo/verushash/vh_hash.cpp -o /tmp/vh_objs/vh_h.o
ar rcs algo/verushash/verushash_all.o /tmp/vh_objs/*.o
rm -rf /tmp/vh_objs

echo "C modules compiled"

# ------------------------------------------------------------------
# Odin build with static lib paths for the linker
# ------------------------------------------------------------------
echo "Building Odin modules..."
EXTRA_LINKER_FLAGS="-lstdc++ -lpthread -ldl -lm \
  ${PWD}/third_party/randomx/lib/linux-x86_64/librandomx.a \
  ${PWD}/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"

odin build . -target:linux_amd64 -o:speed \
  -extra-linker-flags:"$EXTRA_LINKER_FLAGS" \
  -out:frostrig

echo "Build completed!"
