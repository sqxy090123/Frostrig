/*
 * frostrig CryptoNight Heavy/0 plugin
 *
 * cn-heavy/0: 4 MiB memory pool with AES-128-ECB rounds.
 *
 * Build (Linux):
 *   cc -shared -fPIC -march=native \
 *      -I third_party/argon2/include -I third_party/argon2/src \
 *      -I algo -I algo/cryptonight \
 *      plugins/cn_heavy_plugin.c \
 *      algo/cryptonight/cryptonight.c \
 *      third_party/argon2/src/blake2b.c \
 *      -o plugins/cn_heavy_plugin.so
 */
#include "../algo/plugin.h"
#include "../algo/cryptonight/cryptonight.h"

#define CN_HEAVY_PLUGIN_ALGO_ID (FROSTRIG_ALGO_PLUGIN_BASE + 3)

static frostrig_algo_handle *cn_heavy_create(uint32_t config_flags,
                                             int config_huge_pages,
                                             uint32_t config_thread_index,
                                             const void *key, size_t key_size)
{
	(void)config_flags;
	(void)config_thread_index;
	(void)key;
	(void)key_size;
	(void)config_huge_pages;

	frostrig_cryptonight_ctx *c = frostrig_cn_create(FROSTRIG_CN_HEAVY);
	if (c == NULL) {
		return NULL;
	}
	return (frostrig_algo_handle *)c;
}

static void cn_heavy_destroy(frostrig_algo_handle *h)
{
	if (h == NULL) {
		return;
	}
	frostrig_cn_destroy((frostrig_cryptonight_ctx *)h);
}

static int cn_heavy_prepare(frostrig_algo_handle *h,
                            const void *key, size_t key_size)
{
	if (h == NULL) {
		return -1;
	}
	return frostrig_cn_prepare((frostrig_cryptonight_ctx *)h, key, key_size);
}

static int cn_heavy_hash(frostrig_algo_handle *h,
                         const void *input, size_t input_size,
                         frostrig_hash *out)
{
	if (h == NULL || out == NULL) {
		return -1;
	}
	uint8_t digest[32];
	int r = frostrig_cn_hash((frostrig_cryptonight_ctx *)h,
	                          input, input_size, digest);
	if (r != 0) {
		return -1;
	}
	for (size_t i = 0; i < 32; i++) {
		out->bytes[i] = digest[i];
	}
	out->len = 32;
	return 0;
}

static int cn_heavy_pipeline(frostrig_algo_handle *h,
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

		uint8_t digest[32];
		int r = frostrig_cn_hash((frostrig_cryptonight_ctx *)h,
		                           buf, base_len + 8, digest);
		if (r != 0) {
			return -1;
		}
		for (size_t b = 0; b < 32; b++) {
			out[i * 32 + b] = digest[b];
		}
	}
	return 0;
}

static const frostrig_algo_vtable cn_heavy_vtable = {
	.info = {
		.id     = CN_HEAVY_PLUGIN_ALGO_ID,
		.name   = "cn-heavy/0",
		.alias  = "cn_heavy",
		.memory = 4 * 1024 * 1024,
	},
	.create   = cn_heavy_create,
	.destroy  = cn_heavy_destroy,
	.prepare  = cn_heavy_prepare,
	.hash     = cn_heavy_hash,
	.pipeline = cn_heavy_pipeline,
};

const frostrig_algo_vtable *frostrig_algo_register(void)
{
	return &cn_heavy_vtable;
}
