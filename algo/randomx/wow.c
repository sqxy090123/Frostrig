/*
 * frostrig algo module: randomx "wow" variant
 *
 * V2 RandomX: XOR-folds the cache key with the V2 seed constant so the
 * generated dataset differs from the default (variant 0) cache.
 * Uses the same librandomx VM pipeline; only the key schedule differs.
 */
#include "wow.h"

#include <stdlib.h>
#include <string.h>

extern int           randomx_get_flags(void);
extern void        *randomx_alloc_cache(int flags);
extern void         randomx_init_cache(void *cache, const void *key, size_t key_size);
extern void         randomx_release_cache(void *cache);
extern void        *randomx_alloc_dataset(int flags);
extern unsigned long randomx_dataset_item_count(void);
extern void         randomx_init_dataset(void *dataset, void *cache,
                                        unsigned long start, unsigned long count);
extern void         randomx_release_dataset(void *dataset);
extern void        *randomx_create_vm(int flags, void *cache, void *dataset);
extern void         randomx_destroy_vm(void *vm);
extern void         randomx_vm_set_cache(void *vm, void *cache);
extern void         randomx_vm_set_dataset(void *vm, void *dataset);
extern void         randomx_calculate_hash(void *vm, const void *input,
                                          size_t input_size, void *output);
extern void         randomx_calculate_hash_first(void *vm,
                                                const void *input, size_t input_size);
extern void         randomx_calculate_hash_next(void *vm,
                                               const void *next_input,
                                               size_t next_input_size,
                                               void *output);
extern void         randomx_calculate_hash_last(void *vm, void *output);

/* V2 seed constant: first 8 bytes of the "wow" variant identifier,
 * mixed into the cache key before calling randomx_init_cache. */
static const uint8_t wow_v2_seed[8] = {
    0x77, 0x6f, 0x77, 0x00, 0x01, 0x00, 0x00, 0x00
};

struct frostrig_rx_wow_ctx {
    int   flags;
    void *cache;
    void *vm;
};

/* Mix the V2 seed into the raw key to produce the effective cache key. */
static void mix_wow_key(const uint8_t *raw_key, size_t key_size,
                        uint8_t *out)
{
	memset(out, 0, 32);
    for (size_t i = 0; i < key_size && i < 32; i++)
        out[i] = raw_key[i];
    for (int i = 0; i < 8; i++)
        out[i] ^= wow_v2_seed[i];
}

int frostrig_rx_wow_optimal_flags(void)
{
    /* Force V2 bit (128) in addition to the optimal machine flags. */
    return randomx_get_flags() | 128;
}

frostrig_rx_wow_ctx *frostrig_rx_wow_create(int flags,
                                             const void *key, size_t key_size)
{
    int try_flags = flags | 128; /* V2 */
    void *cache = randomx_alloc_cache(try_flags);
    if (cache == NULL && (try_flags & 1)) {
        try_flags &= ~1;
        cache = randomx_alloc_cache(try_flags);
    }
    if (cache == NULL)
        return NULL;

    uint8_t effective_key[32];
    if (key != NULL && key_size > 0)
        mix_wow_key((const uint8_t *)key, key_size, effective_key);
    else
        memset(effective_key, 0, sizeof(effective_key));
    randomx_init_cache(cache, effective_key, sizeof(effective_key));

    void *vm = randomx_create_vm(try_flags, cache, NULL);
    if (vm == NULL) {
        randomx_release_cache(cache);
        return NULL;
    }

    frostrig_rx_wow_ctx *ctx = (frostrig_rx_wow_ctx *)calloc(1, sizeof(*ctx));
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

void frostrig_rx_wow_destroy(frostrig_rx_wow_ctx *ctx)
{
    if (ctx == NULL)
        return;
    if (ctx->vm != NULL)
        randomx_destroy_vm(ctx->vm);
    if (ctx->cache != NULL)
        randomx_release_cache(ctx->cache);
    free(ctx);
}

int frostrig_rx_wow_prepare(frostrig_rx_wow_ctx *ctx,
                            const void *key, size_t key_size)
{
    if (ctx == NULL || key == NULL || key_size == 0)
        return -1;
    uint8_t effective_key[32];
    mix_wow_key((const uint8_t *)key, key_size, effective_key);
    randomx_init_cache(ctx->cache, effective_key, sizeof(effective_key));
    randomx_vm_set_cache(ctx->vm, ctx->cache);
    return 0;
}

int frostrig_rx_wow_hash(frostrig_rx_wow_ctx *ctx,
                         const void *input, size_t input_size,
                         void *output)
{
    if (ctx == NULL || ctx->vm == NULL || input == NULL || output == NULL)
        return -1;
    randomx_calculate_hash(ctx->vm, input, input_size, output);
    return 0;
}

int frostrig_rx_wow_hash_first(frostrig_rx_wow_ctx *ctx,
                                const void *input, size_t input_size)
{
    if (ctx == NULL || ctx->vm == NULL || input == NULL)
        return -1;
    randomx_calculate_hash_first(ctx->vm, input, input_size);
    return 0;
}

int frostrig_rx_wow_hash_next(frostrig_rx_wow_ctx *ctx,
                               const void *next_input, size_t next_input_size,
                               void *output)
{
    if (ctx == NULL || ctx->vm == NULL || next_input == NULL || output == NULL)
        return -1;
    randomx_calculate_hash_next(ctx->vm, next_input, next_input_size, output);
    return 0;
}

int frostrig_rx_wow_hash_last(frostrig_rx_wow_ctx *ctx, void *output)
{
    if (ctx == NULL || ctx->vm == NULL || output == NULL)
        return -1;
    randomx_calculate_hash_last(ctx->vm, output);
    return 0;
}
