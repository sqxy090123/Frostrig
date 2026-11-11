#include "argon2d.h"
#include "argon2_common.h"

static const frostrig_argon2_params argon2d16000_params = {
	.type     = Argon2_d,
	.t_cost   = FROSTRIG_ARGON2D_T_COST,
	.m_cost   = FROSTRIG_ARGON2D_M_COST_16000,
};

static const frostrig_argon2_params argon2d1000_params = {
	.type     = Argon2_d,
	.t_cost   = FROSTRIG_ARGON2D_T_COST,
	.m_cost   = FROSTRIG_ARGON2D_M_COST_1000,
};

frostrig_argon2d16000_ctx *frostrig_argon2d16000_create(void)
{
	return (frostrig_argon2d16000_ctx *)frostrig_argon2_ctx_create(&argon2d16000_params);
}

void frostrig_argon2d16000_destroy(frostrig_argon2d16000_ctx *ctx)
{
	frostrig_argon2_ctx_destroy((frostrig_argon2_ctx *)ctx);
}

int frostrig_argon2d16000_prepare(frostrig_argon2d16000_ctx *ctx, const void *key, size_t key_size)
{
	return frostrig_argon2_ctx_prepare((frostrig_argon2_ctx *)ctx, key, key_size);
}

int frostrig_argon2d16000_hash(frostrig_argon2d16000_ctx *ctx, const void *input, size_t input_size, void *output)
{
	return frostrig_argon2_ctx_hash((frostrig_argon2_ctx *)ctx, input, input_size, output);
}

frostrig_argon2d1000_ctx *frostrig_argon2d1000_create(void)
{
	return (frostrig_argon2d1000_ctx *)frostrig_argon2_ctx_create(&argon2d1000_params);
}

void frostrig_argon2d1000_destroy(frostrig_argon2d1000_ctx *ctx)
{
	frostrig_argon2_ctx_destroy((frostrig_argon2_ctx *)ctx);
}

int frostrig_argon2d1000_prepare(frostrig_argon2d1000_ctx *ctx, const void *key, size_t key_size)
{
	return frostrig_argon2_ctx_prepare((frostrig_argon2_ctx *)ctx, key, key_size);
}

int frostrig_argon2d1000_hash(frostrig_argon2d1000_ctx *ctx, const void *input, size_t input_size, void *output)
{
	return frostrig_argon2_ctx_hash((frostrig_argon2_ctx *)ctx, input, input_size, output);
}
