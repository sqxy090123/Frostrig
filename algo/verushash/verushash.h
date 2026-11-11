#ifndef FROSTRIG_VERUSHASH_H
#define FROSTRIG_VERUSHASH_H

#include <stddef.h>
#include <stdint.h>

/*
 * VerusHash C ABI wrapper.
 *
 * Two solution versions are exposed:
 *   vh/2.2  -> SOLUTION_VERUSHHASH_V2_2 (= 4)
 *   vh/3.1  -> SOLUTION_VERUSHHASH_V2_1 (= 3)
 *
 * Both use the portable Haraka512 implementation (no ISA extension required).
 *
 * Context lifetime:
 *   create()          -> allocates the C++ CVerusHashV2 instance
 *   destroy(ctx)      -> frees the C++ instance
 *   prepare(ctx,key)  -> no-op (VerusHash is stateless between blocks;
 *                         the thread-local key buffer is managed internally)
 *   hash(ctx,input)   -> runs the full streaming hash
 */

typedef struct frostrig_vh_ctx frostrig_vh_ctx;

#ifdef __cplusplus
extern "C" {
#endif

/* --- vh/2.2 (solutionVersion = 4) --- */
frostrig_vh_ctx *frostrig_verushash_v22_create(void);
void             frostrig_verushash_v22_destroy(frostrig_vh_ctx *ctx);
int              frostrig_verushash_v22_prepare(frostrig_vh_ctx *ctx, const void *key, size_t key_size);
int              frostrig_verushash_v22_hash(frostrig_vh_ctx *ctx, const void *input, size_t input_size, void *output);

/* --- vh/3.1 (solutionVersion = 3) --- */
frostrig_vh_ctx *frostrig_verushash_v31_create(void);
void             frostrig_verushash_v31_destroy(frostrig_vh_ctx *ctx);
int              frostrig_verushash_v31_prepare(frostrig_vh_ctx *ctx, const void *key, size_t key_size);
int              frostrig_verushash_v31_hash(frostrig_vh_ctx *ctx, const void *input, size_t input_size, void *output);

#ifdef __cplusplus
}
#endif

#endif /* FROSTRIG_VERUSHASH_H */
