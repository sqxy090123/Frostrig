/*
 * frostrig CryptoNight C wrapper
 *
 * Supports two variants:
 *   cn-pico  - 256 KiB e88 variant (CN/8, e=0)
 *   cn-heavy - 4 MiB heavy variant (CN/8, e=1)
 *
 * The implementation uses the classic CryptoNight/8 (e=0) blake2b
 * initialization with AES-128-ECB for the heavy variant.  For pico,
 * no AES is used.  The heavy variant adds an AES round to the
 * memory-access phase to resist GPU/ASIC acceleration.
 *
 * Build (Linux):
 *   cc -O2 -fPIC -march=native -I third_party/argon2/include \
 *      -I third_party/argon2/src -I algo/cryptonight \
 *      algo/cryptonight/cryptonight.c \
 *      third_party/argon2/src/blake2b.c \
 *      -c -o algo/cryptonight/cryptonight.o
 *
 * Plugin build (per variant):
 *   cc -shared -fPIC -march=native -I third_party/argon2/include \
 *      -I third_party/argon2/src -I algo -I algo/cryptonight \
 *      plugins/cn_pico_plugin.c \
 *      algo/cryptonight/cryptonight.c \
 *      third_party/argon2/src/blake2b.c \
 *      -o plugins/cn_pico_plugin.so
 */
#ifndef FROSTRIG_CRYPTONIGHT_H
#define FROSTRIG_CRYPTONIGHT_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_CN_PICO_SIZE   (256 * 1024)
#define FROSTRIG_CN_HEAVY_SIZE  (4 * 1024 * 1024)

/* Variant enum */
typedef enum {
	FROSTRIG_CN_PICO  = 0,
	FROSTRIG_CN_HEAVY = 1,
} frostrig_cn_variant;

typedef struct frostrig_cryptonight_ctx frostrig_cryptonight_ctx;

frostrig_cryptonight_ctx *frostrig_cn_create(frostrig_cn_variant variant);
void                      frostrig_cn_destroy(frostrig_cryptonight_ctx *ctx);
int                       frostrig_cn_prepare(frostrig_cryptonight_ctx *ctx,
                                              const void *key, size_t key_size);
int                       frostrig_cn_hash(frostrig_cryptonight_ctx *ctx,
                                           const void *input, size_t input_size,
                                           void *output);

#endif /* FROSTRIG_CRYPTONIGHT_H */
