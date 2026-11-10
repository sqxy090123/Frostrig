#ifndef FROSTRIG_RANDOMX_C64_H
#define FROSTRIG_RANDOMX_C64_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_RANDOMX_VARIANT_C64 3

typedef struct frostrig_rx_c64_ctx frostrig_rx_c64_ctx;

int frostrig_rx_c64_optimal_flags(void);
frostrig_rx_c64_ctx *frostrig_rx_c64_create(int flags, const void *key, size_t key_size);
void frostrig_rx_c64_destroy(frostrig_rx_c64_ctx *ctx);
int  frostrig_rx_c64_prepare(frostrig_rx_c64_ctx *ctx, const void *key, size_t key_size);
int  frostrig_rx_c64_hash(frostrig_rx_c64_ctx *ctx, const void *input, size_t input_size, void *output);
int  frostrig_rx_c64_hash_first(frostrig_rx_c64_ctx *ctx, const void *input, size_t input_size);
int  frostrig_rx_c64_hash_next(frostrig_rx_c64_ctx *ctx, const void *next_input, size_t next_input_size, void *output);
int  frostrig_rx_c64_hash_last(frostrig_rx_c64_ctx *ctx, void *output);

#endif
