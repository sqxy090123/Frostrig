/*
 * frostrig algo module: randomx "0" (default) variant
 *
 * Thin C wrapper around librandomx.a that exposes the variant-specific
 * hashing entry points expected by the Odin FFI layer.
 *
 * Each variant under algo/randomx/ ships its own .h/.c pair; the FFI
 * layer includes the .c file directly (foreign include) and links
 * against librandomx.a (foreign import).
 */
#ifndef FROSTRIG_RANDOMX_0_H
#define FROSTRIG_RANDOMX_0_H

#include <stddef.h>
#include <stdint.h>

/* Variant ID: 0 = default / vanilla RandomX (JIT + hard AES). */
#define FROSTRIG_RANDOMX_VARIANT_0 0

/* Opaque handle wrapping a randomx_vm + randomx_cache pair.
 * The variant owns all RandomX resources; the caller never sees them. */
typedef struct frostrig_rx0_ctx frostrig_rx0_ctx;

/*
 * Create a context.
 * flags: randomx_flags (0 = pick optimal for this CPU).
 * key:   32-byte seed (block-height dependent in a real miner; a stable
 *        placeholder here so the cache stays deterministic within a run).
 * Returns NULL on allocation failure.
 */
frostrig_rx0_ctx *frostrig_rx0_create(int flags, const void *key, size_t key_size);

/* Destroy a context and release all associated memory. */
void frostrig_rx0_destroy(frostrig_rx0_ctx *ctx);

/*
 * Compute one RandomX hash.
 * input:    blob + nonce concatenated.
 * output:   receives 32 bytes.
 * Returns 0 on success, -1 on error.
 */
int frostrig_rx0_hash(frostrig_rx0_ctx *ctx,
                     const void *input, size_t input_size,
                     void *output);

/*
 * Pipelined multi-hash: first input primes the pipeline.
 * Returns 0 on success.
 */
int frostrig_rx0_hash_first(frostrig_rx0_ctx *ctx,
                           const void *input, size_t input_size);

/*
 * Pipelined multi-hash: subsequent input; returns previous hash.
 */
int frostrig_rx0_hash_next(frostrig_rx0_ctx *ctx,
                          const void *next_input, size_t next_input_size,
                          void *output);

/*
 * Pipelined multi-hash: drain the final hash.
 */
int frostrig_rx0_hash_last(frostrig_rx0_ctx *ctx, void *output);

/*
 * Re-seed the cache with a new key.  Call before each new job.
 */
int frostrig_rx0_prepare(frostrig_rx0_ctx *ctx,
                         const void *key, size_t key_size);

/*
 * Batch-pipeline `count` sequential-nonce hashes in one call.
 * Nonce start_nonce + i is appended to `input` as 8 little-endian bytes;
 * the i-th hash is written to outputs + i*32 for i in [0, count-2].
 * The final (count-1)-th hash is left pending; drain with
 * frostrig_rx0_hash_last if needed.  Returns 0 on success, -1 on error.
 */
int frostrig_rx0_hash_pipeline(frostrig_rx0_ctx *ctx,
                               const void *input, size_t input_size,
                               uint64_t start_nonce, size_t count,
                               void *outputs);

/*
 * Get the optimal flags for the current machine.
 * Does not include LARGE_PAGES / FULL_MEM / SECURE.
 */
int frostrig_rx0_optimal_flags(void);

#endif /* FROSTRIG_RANDOMX_0_H */
