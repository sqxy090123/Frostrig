/*
 * frostrig BLAKE2b plugin
 *
 * Self-contained shared library exporting the frostrig plugin ABI.
 *
 * Build (Linux):
 *   cc -shared -fPIC -I third_party/argon2/include -I third_party/argon2/src \
 *      -I algo -I algo/blake2b \
 *      plugins/blake2b_plugin.c \
 *      third_party/argon2/src/blake2b.c \
 *      -o plugins/blake2b_plugin.so
 */
#include "../algo/plugin.h"
#include "../algo/blake2b/blake2b.h"

#define BLAKE2B_PLUGIN_ALGO_ID (FROSTRIG_ALGO_PLUGIN_BASE + 1)

static frostrig_algo_handle *blake2b_create(uint32_t config_flags,
                                            int config_huge_pages,
                                            uint32_t config_thread_index,
                                            const void *key, size_t key_size)
{
	(void)config_flags;
	(void)config_huge_pages;
	(void)config_thread_index;
	(void)key;
	(void)key_size;
	frostrig_blake2b_ctx *c = frostrig_blake2b_create();
	if (c == NULL) {
		return NULL;
	}
	return (frostrig_algo_handle *)c;
}

static void blake2b_destroy(frostrig_algo_handle *h)
{
	if (h == NULL) {
		return;
	}
	frostrig_blake2b_destroy((frostrig_blake2b_ctx *)h);
}

static int blake2b_prepare(frostrig_algo_handle *h,
                           const void *key, size_t key_size)
{
	if (h == NULL) {
		return -1;
	}
	return frostrig_blake2b_prepare((frostrig_blake2b_ctx *)h, key, key_size);
}

static int blake2b_hash(frostrig_algo_handle *h,
                       const void *input, size_t input_size,
                       frostrig_hash *out)
{
	if (h == NULL || out == NULL) {
		return -1;
	}
	uint8_t digest[FROSTRIG_BLAKE2B_HASH_LEN];
	int r = frostrig_blake2b_hash((frostrig_blake2b_ctx *)h,
	                              input, input_size, digest);
	if (r != 0) {
		return -1;
	}
	for (size_t i = 0; i < FROSTRIG_BLAKE2B_HASH_LEN; i++) {
		out->bytes[i] = digest[i];
	}
	out->len = FROSTRIG_BLAKE2B_HASH_LEN;
	return 0;
}

static int blake2b_pipeline(frostrig_algo_handle *h,
                           const void *input, size_t input_size,
                           uint64_t start_nonce, size_t count,
                           void *outputs)
{
	if (h == NULL || outputs == NULL || count == 0) {
		return -1;
	}
	uint8_t *out = (uint8_t *)outputs;
	const uint8_t *src = (const uint8_t *)input;

	/*
	 * BLAKE2b has no internal pipeline.  Loop through each nonce,
	 * appending the 8-byte LE nonce to the input buffer, and hash.
	 * This matches the host-side expectation that the pipeline
	 * produces count-1 hashes into outputs.
	 */
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

		uint8_t digest[FROSTRIG_BLAKE2B_HASH_LEN];
		int r = frostrig_blake2b_hash((frostrig_blake2b_ctx *)h,
		                              buf, base_len + 8, digest);
		if (r != 0) {
			return -1;
		}
		for (size_t b = 0; b < FROSTRIG_BLAKE2B_HASH_LEN; b++) {
			out[i * FROSTRIG_BLAKE2B_HASH_LEN + b] = digest[b];
		}
	}
	return 0;
}

static const frostrig_algo_vtable blake2b_vtable = {
	.info = {
		.id     = BLAKE2B_PLUGIN_ALGO_ID,
		.name   = "blake2b",
		.alias  = "blake2",
		.memory = 0,
	},
	.create   = blake2b_create,
	.destroy  = blake2b_destroy,
	.prepare  = blake2b_prepare,
	.hash     = blake2b_hash,
	.pipeline = blake2b_pipeline,
};

const frostrig_algo_vtable *frostrig_algo_register(void)
{
	return &blake2b_vtable;
}
