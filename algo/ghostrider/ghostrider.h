/*
 * frostrig GhostRider C implementation
 *
 * GhostRider is a chameleon-style PoW hash that chains multiple
 * sub-hashes in a dynamic order determined by the block seed.
 * The sub-hash pool includes BLAKE2b, CryptoNight/8, and a
 * fast BLAKE2b-based keystream mixer.
 *
 * The chain length adapts to the seed: longer seeds select longer
 * chains for resistance to GPU acceleration.  The per-thread memory
 * footprint is modest (1 MiB keystream buffer).
 *
 * Build (Linux):
 *   cc -O2 -fPIC -march=native \
 *      -I third_party/argon2/include -I third_party/argon2/src \
 *      -I algo/cryptonight -I algo/ghostrider \
 *      algo/ghostrider/ghostrider.c \
 *      algo/cryptonight/cryptonight.c \
 *      third_party/argon2/src/blake2b.c \
 *      -c -o algo/ghostrider/ghostrider.o
 */
#ifndef FROSTRIG_GHOSTRIDER_H
#define FROSTRIG_GHOSTRIDER_H

#include <stddef.h>
#include <stdint.h>

#define GHOSTRIDER_HASH_LEN 32
#define GHOSTRIDER_MEM_SIZE (1 * 1024 * 1024)

typedef struct frostrig_ghostrider_ctx frostrig_ghostrider_ctx;

frostrig_ghostrider_ctx *frostrig_ghostrider_create(void);
void                     frostrig_ghostrider_destroy(frostrig_ghostrider_ctx *ctx);
int                      frostrig_ghostrider_prepare(frostrig_ghostrider_ctx *ctx,
                                                      const void *key, size_t key_size);
int                      frostrig_ghostrider_hash(frostrig_ghostrider_ctx *ctx,
                                                   const void *input, size_t input_size,
                                                   void *output);

#endif /* FROSTRIG_GHOSTRIDER_H */
