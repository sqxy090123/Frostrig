/*
 * frostrig algo module: randomx "0" (default) variant
 *
 * Implementation of the API declared in 0.h.
 * Wraps librandomx (C API) with a per-thread VM context.
 */
#include "0.h"

#include <stdlib.h>
#include <string.h>

/* The RandomX C API (provided by librandomx.a). */
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

struct frostrig_rx0_ctx {
    int     flags;
    void   *cache;   /* randomx_cache * */
    void   *vm;      /* randomx_vm *   */
};

int frostrig_rx0_optimal_flags(void)
{
    return randomx_get_flags();
}

frostrig_rx0_ctx *frostrig_rx0_create(int flags, const void *key, size_t key_size)
{
    /* Try with huge pages; fall back without if allocation fails. */
    int try_flags = flags;
    void *cache   = randomx_alloc_cache(try_flags);
    if (cache == NULL && (try_flags & 1) /* LARGE_PAGES */) {
        try_flags &= ~1;
        cache = randomx_alloc_cache(try_flags);
    }
    if (cache == NULL)
        return NULL;

    if (key != NULL && key_size > 0)
        randomx_init_cache(cache, key, key_size);

    void *vm = randomx_create_vm(try_flags, cache, NULL);
    if (vm == NULL) {
        randomx_release_cache(cache);
        return NULL;
    }

    frostrig_rx0_ctx *ctx = (frostrig_rx0_ctx *)calloc(1, sizeof(*ctx));
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

void frostrig_rx0_destroy(frostrig_rx0_ctx *ctx)
{
    if (ctx == NULL)
        return;
    if (ctx->vm != NULL)
        randomx_destroy_vm(ctx->vm);
    if (ctx->cache != NULL)
        randomx_release_cache(ctx->cache);
    free(ctx);
}

int frostrig_rx0_prepare(frostrig_rx0_ctx *ctx,
                        const void *key, size_t key_size)
{
    if (ctx == NULL || key == NULL || key_size == 0)
        return -1;
    randomx_init_cache(ctx->cache, key, key_size);
    if (ctx->flags & 4 /* FULL_MEM */) {
        void *dataset = randomx_alloc_dataset(ctx->flags);
        if (dataset == NULL)
            return -1;
        randomx_init_dataset(dataset, ctx->cache, 0, randomx_dataset_item_count());
        randomx_vm_set_dataset(ctx->vm, dataset);
        /* Dataset is owned by the VM; no separate free needed here. */
    } else {
        randomx_vm_set_cache(ctx->vm, ctx->cache);
    }
    return 0;
}

int frostrig_rx0_hash(frostrig_rx0_ctx *ctx,
                     const void *input, size_t input_size,
                     void *output)
{
    if (ctx == NULL || ctx->vm == NULL || input == NULL || output == NULL)
        return -1;
    randomx_calculate_hash(ctx->vm, input, input_size, output);
    return 0;
}

int frostrig_rx0_hash_first(frostrig_rx0_ctx *ctx,
                           const void *input, size_t input_size)
{
    if (ctx == NULL || ctx->vm == NULL || input == NULL)
        return -1;
    randomx_calculate_hash_first(ctx->vm, input, input_size);
    return 0;
}

int frostrig_rx0_hash_next(frostrig_rx0_ctx *ctx,
                          const void *next_input, size_t next_input_size,
                          void *output)
{
    if (ctx == NULL || ctx->vm == NULL || next_input == NULL || output == NULL)
        return -1;
    randomx_calculate_hash_next(ctx->vm, next_input, next_input_size, output);
    return 0;
}

int frostrig_rx0_hash_last(frostrig_rx0_ctx *ctx, void *output)
{
    if (ctx == NULL || ctx->vm == NULL || output == NULL)
        return -1;
    randomx_calculate_hash_last(ctx->vm, output);
    return 0;
}
