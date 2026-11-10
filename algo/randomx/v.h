#ifndef FROSTRIG_RANDOMX_V_H
#define FROSTRIG_RANDOMX_V_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_RANDOMX_VARIANT_V 4

typedef struct frostrig_rx_v_ctx frostrig_rx_v_ctx;

int frostrig_rx_v_optimal_flags(void);
frostrig_rx_v_ctx *frostrig_rx_v_create(int flags, const void *key, size_t key_size);
void frostrig_rx_v_destroy(frostrig_rx_v_ctx *ctx);
int  frostrig_rx_v_prepare(frostrig_rx_v_ctx *ctx, const void *key, size_t key_size);
int  frostrig_rx_v_hash(frostrig_rx_v_ctx *ctx, const void *input, size_t input_size, void *output);
int  frostrig_rx_v_hash_first(frostrig_rx_v_ctx *ctx, const void *input, size_t input_size);
int  frostrig_rx_v_hash_next(frostrig_rx_v_ctx *ctx, const void *next_input, size_t next_input_size, void *output);
int  frostrig_rx_v_hash_last(frostrig_rx_v_ctx *ctx, void *output);

#endif
