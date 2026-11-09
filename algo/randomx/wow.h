/*
 * frostrig algo module: randomx "wow" variant
 *
 * RandomX V2 (wow): same core pipeline as variant 0, but the cache key
 * is XOR-folded with the V2 seed constant so the dataset differs from
 * the default variant.  Used by pools that have migrated to the V2
 * flag set.
 */
#ifndef FROSTRIG_RANDOMX_WOW_H
#define FROSTRIG_RANDOMX_WOW_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_RANDOMX_VARIANT_WOW 1

/* Opaque handle — same layout as the 0 variant but with a different
 * cache key schedule. */
typedef struct frostrig_rx_wow_ctx frostrig_rx_wow_ctx;

int frostrig_rx_wow_optimal_flags(void);

frostrig_rx_wow_ctx *frostrig_rx_wow_create(int flags,
                                             const void *key, size_t key_size);
void frostrig_rx_wow_destroy(frostrig_rx_wow_ctx *ctx);
int  frostrig_rx_wow_prepare(frostrig_rx_wow_ctx *ctx,
                             const void *key, size_t key_size);
int  frostrig_rx_wow_hash(frostrig_rx_wow_ctx *ctx,
                          const void *input, size_t input_size,
                          void *output);
int  frostrig_rx_wow_hash_first(frostrig_rx_wow_ctx *ctx,
                                 const void *input, size_t input_size);
int  frostrig_rx_wow_hash_next(frostrig_rx_wow_ctx *ctx,
                                const void *next_input, size_t next_input_size,
                                void *output);
int  frostrig_rx_wow_hash_last(frostrig_rx_wow_ctx *ctx, void *output);

#endif /* FROSTRIG_RANDOMX_WOW_H */
