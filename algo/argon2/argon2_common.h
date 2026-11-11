#ifndef FROSTRIG_ARGON2_COMMON_H
#define FROSTRIG_ARGON2_COMMON_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <argon2.h>

/* Argon2d m_cost constants (KiB). */
#define FROSTRIG_ARGON2D_M_COST_16000  16000u
#define FROSTRIG_ARGON2D_M_COST_1000   1000u

/* Fixed iteration counts (t_cost) for the frostrig Argon2 variants.
 * These are the canonical PoW-style parameters used by the
 * corresponding coins. */
#define FROSTRIG_ARGON2_ID_T_COST  3u
#define FROSTRIG_ARGON2D_T_COST    1u
#define FROSTRIG_ARGON2_PARALLELISM 1u
#define FROSTRIG_ARGON2_HASH_LEN  32u

typedef struct {
	argon2_type type;
	uint32_t    t_cost;
	uint32_t    m_cost;
} frostrig_argon2_params;

/* frostrig_argon2_hash: one-shot Argon2 hash, no persistent state needed.
 * pwd/pwdlen: data to hash (e.g. blob + nonce).
 * salt/saltlen: fixed salt (empty = zeroed).
 * out: receives `out_len` bytes of raw hash.
 * Returns 0 on success, -1 on failure. */
static inline int frostrig_argon2_hash(const frostrig_argon2_params *p,
                                      const void *pwd, size_t pwdlen,
                                      const void *salt, size_t saltlen,
                                      void *out, size_t out_len)
{
	int r = argon2_hash(p->t_cost, p->m_cost, FROSTRIG_ARGON2_PARALLELISM,
	                    pwd, pwdlen, salt, saltlen,
	                    out, out_len,
	                    NULL, 0,
	                    p->type, ARGON2_VERSION_13);
	return (r == ARGON2_OK) ? 0 : -1;
}

/* Context wrapper for per-thread Argon2 handle.
 * Argon2 requires no persistent state (each call is stateless),
 * but we keep a small struct so the FFI layer can use the same
 * create/destroy/prepare/hash interface as RandomX variants. */
typedef struct {
	frostrig_argon2_params params;
} frostrig_argon2_ctx;

static inline frostrig_argon2_ctx *frostrig_argon2_ctx_create(
	const frostrig_argon2_params *params)
{
	if (params == NULL)
		return NULL;
	frostrig_argon2_ctx *ctx = (frostrig_argon2_ctx *)malloc(sizeof(*ctx));
	if (ctx == NULL)
		return NULL;
	ctx->params = *params;
	return ctx;
}

static inline void frostrig_argon2_ctx_destroy(frostrig_argon2_ctx *ctx)
{
	free(ctx);
}

/* prepare is a no-op for Argon2 (stateless); returns 0. */
static inline int frostrig_argon2_ctx_prepare(frostrig_argon2_ctx *ctx,
                                              const void *key, size_t key_size)
{
	(void)ctx; (void)key; (void)key_size;
	return 0;
}

/* hash: computes one Argon2 hash over input (pwd = input || nonce). */
static inline int frostrig_argon2_ctx_hash(frostrig_argon2_ctx *ctx,
                                          const void *input, size_t input_size,
                                          void *output)
{
	if (ctx == NULL || input == NULL || output == NULL)
		return -1;
	return frostrig_argon2_hash(&ctx->params, input, input_size,
	                             NULL, 0, output, FROSTRIG_ARGON2_HASH_LEN);
}

#endif /* FROSTRIG_ARGON2_COMMON_H */
