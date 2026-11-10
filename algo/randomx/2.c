#include "2.h"
#include "rx_common.h"

#define RX_FLAG_V2 128

int frostrig_rx2_optimal_flags(void)
{
	return randomx_get_flags() | RX_FLAG_V2;
}

frostrig_rx2_ctx *frostrig_rx2_create(int flags, const void *key, size_t key_size)
{
	return (frostrig_rx2_ctx *)frostrig_rx_ctx_create(flags, RX_FLAG_V2, key, key_size, NULL);
}

void frostrig_rx2_destroy(frostrig_rx2_ctx *ctx)
{
	frostrig_rx_ctx_destroy((frostrig_rx_ctx *)ctx);
}

int frostrig_rx2_prepare(frostrig_rx2_ctx *ctx, const void *key, size_t key_size)
{
	return frostrig_rx_ctx_prepare((frostrig_rx_ctx *)ctx, key, key_size, NULL);
}

int frostrig_rx2_hash(frostrig_rx2_ctx *ctx, const void *input, size_t input_size, void *output)
{
	return frostrig_rx_ctx_hash((frostrig_rx_ctx *)ctx, input, input_size, output);
}

int frostrig_rx2_hash_first(frostrig_rx2_ctx *ctx, const void *input, size_t input_size)
{
	return frostrig_rx_ctx_hash_first((frostrig_rx_ctx *)ctx, input, input_size);
}

int frostrig_rx2_hash_next(frostrig_rx2_ctx *ctx, const void *next_input, size_t next_input_size, void *output)
{
	return frostrig_rx_ctx_hash_next((frostrig_rx_ctx *)ctx, next_input, next_input_size, output);
}

int frostrig_rx2_hash_last(frostrig_rx2_ctx *ctx, void *output)
{
	return frostrig_rx_ctx_hash_last((frostrig_rx_ctx *)ctx, output);
}
