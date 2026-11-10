#ifndef FROSTRIG_RANDOMX_2_H
#define FROSTRIG_RANDOMX_2_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_RANDOMX_VARIANT_2 2

typedef struct frostrig_rx2_ctx frostrig_rx2_ctx;

int frostrig_rx2_optimal_flags(void);
frostrig_rx2_ctx *frostrig_rx2_create(int flags, const void *key, size_t key_size);
void frostrig_rx2_destroy(frostrig_rx2_ctx *ctx);
int  frostrig_rx2_prepare(frostrig_rx2_ctx *ctx, const void *key, size_t key_size);
int  frostrig_rx2_hash(frostrig_rx2_ctx *ctx, const void *input, size_t input_size, void *output);
int  frostrig_rx2_hash_first(frostrig_rx2_ctx *ctx, const void *input, size_t input_size);
int  frostrig_rx2_hash_next(frostrig_rx2_ctx *ctx, const void *next_input, size_t next_input_size, void *output);
int  frostrig_rx2_hash_last(frostrig_rx2_ctx *ctx, void *output);

#endif
