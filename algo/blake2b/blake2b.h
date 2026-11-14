/*
 * frostrig BLAKE2b PoW wrapper
 *
 * BLAKE2b is used as a CPU-friendly PoW hash (BIP-110).  The wrapper
 * exposes the same create/destroy/prepare/hash contract as the other
 * frostrig algorithm modules.  Because BLAKE2b is stateless, prepare is
 * a no-op and the context carries only the output length.
 *
 * Build (Linux):
 *   cc -O2 -fPIC -I third_party/argon2/include -I third_party/argon2/src \
 *      -I algo/blake2b \
 *      algo/blake2b/blake2b.c \
 *      third_party/argon2/src/blake2b.c \
 *      -c -o algo/blake2b/blake2b.o
 *
 * Plugin build:
 *   cc -shared -fPIC -I algo -I third_party/argon2/src \
 *      plugins/blake2b_plugin.c third_party/argon2/src/blake2b.c \
 *      -o plugins/blake2b_plugin.so
 */
#ifndef FROSTRIG_BLAKE2B_H
#define FROSTRIG_BLAKE2B_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_BLAKE2B_HASH_LEN 32

typedef struct frostrig_blake2b_ctx frostrig_blake2b_ctx;

frostrig_blake2b_ctx *frostrig_blake2b_create(void);
void                  frostrig_blake2b_destroy(frostrig_blake2b_ctx *ctx);
int                   frostrig_blake2b_prepare(frostrig_blake2b_ctx *ctx,
                                                const void *key, size_t key_size);
int                   frostrig_blake2b_hash(frostrig_blake2b_ctx *ctx,
                                             const void *input, size_t input_size,
                                             void *output);

#endif /* FROSTRIG_BLAKE2B_H */
