/*
 * demo algorithm plugin for frostrig
 *
 * A self-contained shared library that exports the frostrig plugin ABI
 * (algo/plugin.h).  It wraps the default RandomX variant (rx/0) using
 * librandomx, demonstrating the host-side dlopen/dlsym loading path.
 *
 * Build (Linux):
 *   cc -shared -fPIC -Ithird_party/randomx/include -Ialgo \
 *      plugins/demo.c \
 *      third_party/randomx/lib/linux-x86_64/librandomx.a \
 *      -lstdc++ -lpthread -ldl -lm -o plugins/demo.so
 */
#include "../algo/plugin.h"
#include "../third_party/randomx/include/randomx.h"
#include <stdio.h>
#include <stdlib.h>

#define DEMO_PLUGIN_ALGO_ID FROSTRIG_ALGO_PLUGIN_BASE

typedef struct {
	randomx_vm    *vm;
	randomx_cache *cache;
} demo_ctx;

static frostrig_algo_handle *demo_create(uint32_t config_flags,
                                         int config_huge_pages,
                                         uint32_t config_thread_index,
                                         const void *key, size_t key_size)
{
	(void)config_thread_index;
	demo_ctx *c = (demo_ctx *)calloc(1, sizeof(demo_ctx));
	if (c == NULL) {
		return NULL;
	}
	randomx_flags f = randomx_get_flags();
	if (config_huge_pages) {
		f |= RANDOMX_FLAG_LARGE_PAGES;
	}
	c->cache = randomx_alloc_cache(f);
	if (c->cache == NULL) {
		f &= ~RANDOMX_FLAG_LARGE_PAGES;
		c->cache = randomx_alloc_cache(f);
	}
	if (c->cache == NULL) {
		fprintf(stderr, "[demo] alloc_cache failed\n");
		free(c);
		return NULL;
	}
	c->vm = randomx_create_vm(f, c->cache, NULL);
	if (c->vm == NULL) {
		fprintf(stderr, "[demo] create_vm failed\n");
		randomx_release_cache(c->cache);
		free(c);
		return NULL;
	}
	randomx_init_cache(c->cache, key, key_size > 0 ? key_size : 32);
	return (frostrig_algo_handle *)c;
}

static void demo_destroy(frostrig_algo_handle *h)
{
	if (h == NULL)
		return;
	demo_ctx *c = (demo_ctx *)h;
	if (c->vm != NULL)
		randomx_destroy_vm(c->vm);
	if (c->cache != NULL)
		randomx_release_cache(c->cache);
	free(c);
}

static int demo_prepare(frostrig_algo_handle *h, const void *key, size_t key_size)
{
	if (h == NULL)
		return -1;
	demo_ctx *c = (demo_ctx *)h;
	randomx_init_cache(c->cache, key, key_size > 0 ? key_size : 32);
	return 0;
}

static int demo_hash(frostrig_algo_handle *h, const void *input,
                     size_t input_size, frostrig_hash *out)
{
	if (h == NULL || out == NULL)
		return -1;
	demo_ctx *c = (demo_ctx *)h;
	uint8_t result[RANDOMX_HASH_SIZE];
	randomx_calculate_hash(c->vm, input, input_size, result);
	for (size_t i = 0; i < RANDOMX_HASH_SIZE; i++)
		out->bytes[i] = result[i];
	out->len = RANDOMX_HASH_SIZE;
	return 0;
}

static int demo_pipeline(frostrig_algo_handle *h, const void *input,
                         size_t input_size, uint64_t start_nonce,
                         size_t count, void *outputs)
{
	if (h == NULL || outputs == NULL || count == 0)
		return -1;
	demo_ctx *c = (demo_ctx *)h;
	uint8_t *out = (uint8_t *)outputs;
	const uint8_t *src = (const uint8_t *)input;
	uint8_t buf[4096];
	size_t base_len = input_size;
	if (base_len + 8 > sizeof(buf))
		base_len = sizeof(buf) - 8;

	/* Build the first (nonce=start_nonce) input and prime the pipeline. */
	for (size_t i = 0; i < base_len; i++)
		buf[i] = src[i];
	uint8_t *nb = buf + base_len;
	for (int k = 0; k < 8; k++)
		nb[k] = (uint8_t)((start_nonce >> (k * 8)) & 0xff);
	randomx_calculate_hash_first(c->vm, buf, base_len + 8);

	/* For each subsequent nonce, output the previous hash and prime next. */
	uint8_t result[RANDOMX_HASH_SIZE];
	for (size_t i = 0; i + 1 < count; i++) {
		uint64_t n = start_nonce + i + 1;
		for (size_t j = 0; j < base_len; j++)
			buf[j] = src[j];
		uint8_t *nb2 = buf + base_len;
		for (int k = 0; k < 8; k++)
			nb2[k] = (uint8_t)((n >> (k * 8)) & 0xff);
		randomx_calculate_hash_next(c->vm, buf, base_len + 8, result);
		for (size_t b = 0; b < RANDOMX_HASH_SIZE; b++)
			out[i * RANDOMX_HASH_SIZE + b] = result[b];
	}
	/* The final (count-1)-th hash is left pending; the host drains it
	 * with a follow-up randomx_calculate_hash_last if it needs the value. */
	(void)randomx_calculate_hash_last;
	return 0;
}

static const frostrig_algo_vtable demo_vtable = {
	.info = {
		.id     = DEMO_PLUGIN_ALGO_ID,
		.name   = "rx0-plugin",
		.alias  = "rx0plg",
		.memory = (uint64_t)2336 * 1024 * 1024,
	},
	.create   = demo_create,
	.destroy  = demo_destroy,
	.prepare  = demo_prepare,
	.hash     = demo_hash,
	.pipeline = demo_pipeline,
};

const frostrig_algo_vtable *frostrig_algo_register(void)
{
	return &demo_vtable;
}
