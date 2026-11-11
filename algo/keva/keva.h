#ifndef FROSTRIG_RANDOMX_KEVA_H
#define FROSTRIG_RANDOMX_KEVA_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_RANDOMX_VARIANT_KEVA 7

typedef struct frostrig_rx_keva_ctx frostrig_rx_keva_ctx;

int frostrig_rx_keva_optimal_flags(void);
frostrig_rx_keva_ctx *frostrig_rx_keva_create(int flags, const void *key, size_t key_size);
void frostrig_rx_keva_destroy(frostrig_rx_keva_ctx *ctx);
int  frostrig_rx_keva_prepare(frostrig_rx_keva_ctx *ctx, const void *key, size_t key_size);
int  frostrig_rx_keva_hash(frostrig_rx_keva_ctx *ctx, const void *input, size_t input_size, void *output);
int  frostrig_rx_keva_hash_first(frostrig_rx_keva_ctx *ctx, const void *input, size_t input_size);
int  frostrig_rx_keva_hash_next(frostrig_rx_keva_ctx *ctx, const void *next_input, size_t next_input_size, void *output);
int  frostrig_rx_keva_hash_last(frostrig_rx_keva_ctx *ctx, void *output);

#endif
