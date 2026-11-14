/*
 * frostrig BLAKE2b PoW C wrapper
 *
 * Stateless BLAKE2b hash.  The context is an empty marker so the FFI
 * layer can use the same create/destroy/prepare/hash interface as the
 * stateful algorithms (RandomX, CryptoNight).
 */
#include "blake2b.h"
#include <stdlib.h>

/* Include the Argon2-tree BLAKE2b.  The header declares blake2b(). */
#include <blake2.h>

typedef struct frostrig_blake2b_ctx {
	int dummy; /* keep the struct non-empty */
} frostrig_blake2b_ctx;

frostrig_blake2b_ctx *frostrig_blake2b_create(void)
{
	frostrig_blake2b_ctx *c = (frostrig_blake2b_ctx *)malloc(sizeof(*c));
	if (c == NULL) {
		return NULL;
	}
	c->dummy = 0;
	return c;
}

void frostrig_blake2b_destroy(frostrig_blake2b_ctx *ctx)
{
	free(ctx);
}

int frostrig_blake2b_prepare(frostrig_blake2b_ctx *ctx,
                             const void *key, size_t key_size)
{
	(void)key;
	(void)key_size;
	if (ctx == NULL) {
		return -1;
	}
	return 0;
}

int frostrig_blake2b_hash(frostrig_blake2b_ctx *ctx,
                          const void *input, size_t input_size,
                          void *output)
{
	if (ctx == NULL || input == NULL || output == NULL || input_size == 0) {
		return -1;
	}
	int r = blake2b(output, FROSTRIG_BLAKE2B_HASH_LEN,
	                input, input_size, NULL, 0);
	return (r == 0) ? 0 : -1;
}
