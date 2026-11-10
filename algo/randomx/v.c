#include "v.h"
#include "rx_common.h"

static const uint8_t v_salt[8] = { 'M', 'O', 'N', 'E', 'R', 'O', 'V', 0 };

static void mix_v_key(const uint8_t *raw, size_t n, uint8_t out[32])
{
	frostrig_rx_xor_salt(raw, n, out, v_salt, sizeof(v_salt));
}

int frostrig_rx_v_optimal_flags(void)
{
	return randomx_get_flags();
}

frostrig_rx_v_ctx *frostrig_rx_v_create(int flags, const void *key, size_t key_size)
{
	return (frostrig_rx_v_ctx *)frostrig_rx_ctx_create(flags, 0, key, key_size, mix_v_key);
}

void frostrig_rx_v_destroy(frostrig_rx_v_ctx *ctx)
{
	frostrig_rx_ctx_destroy((frostrig_rx_ctx *)ctx);
}

int frostrig_rx_v_prepare(frostrig_rx_v_ctx *ctx, const void *key, size_t key_size)
{
	return frostrig_rx_ctx_prepare((frostrig_rx_ctx *)ctx, key, key_size, mix_v_key);
}

int frostrig_rx_v_hash(frostrig_rx_v_ctx *ctx, const void *input, size_t input_size, void *output)
{
	return frostrig_rx_ctx_hash((frostrig_rx_ctx *)ctx, input, input_size, output);
}

int frostrig_rx_v_hash_first(frostrig_rx_v_ctx *ctx, const void *input, size_t input_size)
{
	return frostrig_rx_ctx_hash_first((frostrig_rx_ctx *)ctx, input, input_size);
}

int frostrig_rx_v_hash_next(frostrig_rx_v_ctx *ctx, const void *next_input, size_t next_input_size, void *output)
{
	return frostrig_rx_ctx_hash_next((frostrig_rx_ctx *)ctx, next_input, next_input_size, output);
}

int frostrig_rx_v_hash_last(frostrig_rx_v_ctx *ctx, void *output)
{
	return frostrig_rx_ctx_hash_last((frostrig_rx_ctx *)ctx, output);
}
