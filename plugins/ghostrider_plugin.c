/*
 * frostrig GhostRider plugin
 *
 * Chameleon-style PoW hash with dynamic sub-hash chain.
 *
 * Build (Linux):
 *   cc -shared -fPIC -march=native \
 *      -I third_party/argon2/include -I third_party/argon2/src \
 *      -I algo -I algo/ghostrider \
 *      plugins/ghostrider_plugin.c \
 *      algo/ghostrider/ghostrider.c \
 *      third_party/argon2/src/blake2b.c \
 *      -o plugins/ghostrider_plugin.so
 */
#include "../algo/plugin.h"
#include "../algo/ghostrider/ghostrider.h"

#define GHOSTRIDER_PLUGIN_ALGO_ID (FROSTRIG_ALGO_PLUGIN_BASE + 4)

static frostrig_algo_handle *gr_create(uint32_t config_flags,
                                       int config_huge_pages,
                                       uint32_t config_thread_index,
                                       const void *key, size_t key_size)
{
	(void)config_flags;
	(void)config_thread_index;
	(void)key;
	(void)key_size;
	(void)config_huge_pages;

	frostrig_ghostrider_ctx *c = frostrig_ghostrider_create();
	if (c == NULL) {
		return NULL;
	}
	return (frostrig_algo_handle *)c;
}

static void gr_destroy(frostrig_algo_handle *h)
{
	if (h == NULL) {
		return;
	}
	frostrig_ghostrider_destroy((frostrig_ghostrider_ctx *)h);
}

static int gr_prepare(frostrig_algo_handle *h,
                      const void *key, size_t key_size)
{
	if (h == NULL) {
		return -1;
	}
	return frostrig_ghostrider_prepare((frostrig_ghostrider_ctx *)h,
	                                     key, key_size);
}

static int gr_hash(frostrig_algo_handle *h,
                   const void *input, size_t input_size,
                   frostrig_hash *out)
{
	if (h == NULL || out == NULL) {
		return -1;
	}
	uint8_t digest[GHOSTRIDER_HASH_LEN];
	int r = frostrig_ghostrider_hash((frostrig_ghostrider_ctx *)h,
	                                  input, input_size, digest);
	if (r != 0) {
		return -1;
	}
	for (size_t i = 0; i < GHOSTRIDER_HASH_LEN; i++) {
		out->bytes[i] = digest[i];
	}
	out->len = GHOSTRIDER_HASH_LEN;
	return 0;
}

static int gr_pipeline(frostrig_algo_handle *h,
                       const void *input, size_t input_size,
                       uint64_t start_nonce, size_t count,
                       void *outputs)
{
	if (h == NULL || outputs == NULL || count == 0) {
		return -1;
	}
	uint8_t *out = (uint8_t *)outputs;
	const uint8_t *src = (const uint8_t *)input;

	uint8_t buf[4096];
	size_t base_len = input_size;
	if (base_len + 8 > sizeof(buf)) {
		base_len = sizeof(buf) - 8;
	}

	for (size_t i = 0; i + 1 < count; i++) {
		uint64_t n = start_nonce + i + 1;
		for (size_t j = 0; j < base_len; j++) {
			buf[j] = src[j];
		}
		uint8_t *nb = buf + base_len;
		for (int k = 0; k < 8; k++) {
			nb[k] = (uint8_t)((n >> (k * 8)) & 0xff);
		}

		uint8_t digest[GHOSTRIDER_HASH_LEN];
		int r = frostrig_ghostrider_hash((frostrig_ghostrider_ctx *)h,
		                                   buf, base_len + 8, digest);
		if (r != 0) {
			return -1;
		}
		for (size_t b = 0; b < GHOSTRIDER_HASH_LEN; b++) {
			out[i * GHOSTRIDER_HASH_LEN + b] = digest[b];
		}
	}
	return 0;
}

static const frostrig_algo_vtable gr_vtable = {
	.info = {
		.id     = GHOSTRIDER_PLUGIN_ALGO_ID,
		.name   = "ghostrider",
		.alias  = "gr",
		.memory = 1 * 1024 * 1024,
	},
	.create   = gr_create,
	.destroy  = gr_destroy,
	.prepare  = gr_prepare,
	.hash     = gr_hash,
	.pipeline = gr_pipeline,
};

const frostrig_algo_vtable *frostrig_algo_register(void)
{
	return &gr_vtable;
}
