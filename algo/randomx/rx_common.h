#ifndef FROSTRIG_RX_COMMON_H
#define FROSTRIG_RX_COMMON_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern int            randomx_get_flags(void);
extern void          *randomx_alloc_cache(int flags);
extern void           randomx_init_cache(void *cache, const void *key, size_t key_size);
extern void           randomx_release_cache(void *cache);
extern void          *randomx_alloc_dataset(int flags);
extern unsigned long  randomx_dataset_item_count(void);
extern void           randomx_init_dataset(void *dataset, void *cache,
                                           unsigned long start, unsigned long count);
extern void           randomx_release_dataset(void *dataset);
extern void          *randomx_create_vm(int flags, void *cache, void *dataset);
extern void           randomx_destroy_vm(void *vm);
extern void           randomx_vm_set_cache(void *vm, void *cache);
extern void           randomx_vm_set_dataset(void *vm, void *dataset);
extern void           randomx_calculate_hash(void *vm, const void *input,
                                             size_t input_size, void *output);
extern void           randomx_calculate_hash_first(void *vm,
                                                   const void *input, size_t input_size);
extern void           randomx_calculate_hash_next(void *vm,
                                                  const void *next_input,
                                                  size_t next_input_size,
                                                  void *output);
extern void           randomx_calculate_hash_last(void *vm, void *output);

typedef void (*frostrig_rx_mix_fn)(const uint8_t *raw, size_t n, uint8_t out[32]);

typedef struct {
	int   flags;
	void *cache;
	void *vm;
} frostrig_rx_ctx;

static inline void frostrig_rx_copy_key(const uint8_t *raw, size_t n, uint8_t out[32])
{
	memset(out, 0, 32);
	if (raw != NULL && n > 0) {
		size_t m = n < 32 ? n : 32;
		memcpy(out, raw, m);
	}
}

static inline void frostrig_rx_xor_salt(const uint8_t *raw, size_t n, uint8_t out[32],
                                        const uint8_t *salt, size_t salt_n)
{
	frostrig_rx_copy_key(raw, n, out);
	for (size_t i = 0; i < salt_n && i < 32; i++)
		out[i] ^= salt[i];
}

static inline frostrig_rx_ctx *frostrig_rx_ctx_create(int flags, int extra_flags,
                                                      const void *key, size_t key_size,
                                                      frostrig_rx_mix_fn mix)
{
	int try_flags = flags | extra_flags;
	void *cache = randomx_alloc_cache(try_flags);
	if (cache == NULL && (try_flags & 1)) {
		try_flags &= ~1;
		cache = randomx_alloc_cache(try_flags);
	}
	if (cache == NULL)
		return NULL;

	uint8_t effective_key[32];
	if (mix != NULL)
		mix((const uint8_t *)key, key_size, effective_key);
	else
		frostrig_rx_copy_key((const uint8_t *)key, key_size, effective_key);
	randomx_init_cache(cache, effective_key, sizeof(effective_key));

	void *vm = randomx_create_vm(try_flags, cache, NULL);
	if (vm == NULL) {
		randomx_release_cache(cache);
		return NULL;
	}

	frostrig_rx_ctx *ctx = (frostrig_rx_ctx *)calloc(1, sizeof(*ctx));
	if (ctx == NULL) {
		randomx_destroy_vm(vm);
		randomx_release_cache(cache);
		return NULL;
	}
	ctx->flags = try_flags;
	ctx->cache = cache;
	ctx->vm    = vm;
	return ctx;
}

static inline void frostrig_rx_ctx_destroy(frostrig_rx_ctx *ctx)
{
	if (ctx == NULL)
		return;
	if (ctx->vm != NULL)
		randomx_destroy_vm(ctx->vm);
	if (ctx->cache != NULL)
		randomx_release_cache(ctx->cache);
	free(ctx);
}

static inline int frostrig_rx_ctx_prepare(frostrig_rx_ctx *ctx,
                                          const void *key, size_t key_size,
                                          frostrig_rx_mix_fn mix)
{
	if (ctx == NULL || key == NULL || key_size == 0)
		return -1;
	uint8_t effective_key[32];
	if (mix != NULL)
		mix((const uint8_t *)key, key_size, effective_key);
	else
		frostrig_rx_copy_key((const uint8_t *)key, key_size, effective_key);
	randomx_init_cache(ctx->cache, effective_key, sizeof(effective_key));
	randomx_vm_set_cache(ctx->vm, ctx->cache);
	return 0;
}

static inline int frostrig_rx_ctx_hash(frostrig_rx_ctx *ctx,
                                       const void *input, size_t input_size,
                                       void *output)
{
	if (ctx == NULL || ctx->vm == NULL || input == NULL || output == NULL)
		return -1;
	randomx_calculate_hash(ctx->vm, input, input_size, output);
	return 0;
}

static inline int frostrig_rx_ctx_hash_first(frostrig_rx_ctx *ctx,
                                             const void *input, size_t input_size)
{
	if (ctx == NULL || ctx->vm == NULL || input == NULL)
		return -1;
	randomx_calculate_hash_first(ctx->vm, input, input_size);
	return 0;
}

static inline int frostrig_rx_ctx_hash_next(frostrig_rx_ctx *ctx,
                                            const void *next_input, size_t next_input_size,
                                            void *output)
{
	if (ctx == NULL || ctx->vm == NULL || next_input == NULL || output == NULL)
		return -1;
	randomx_calculate_hash_next(ctx->vm, next_input, next_input_size, output);
	return 0;
}

static inline int frostrig_rx_ctx_hash_last(frostrig_rx_ctx *ctx, void *output)
{
	if (ctx == NULL || ctx->vm == NULL || output == NULL)
		return -1;
	randomx_calculate_hash_last(ctx->vm, output);
	return 0;
}

#endif
