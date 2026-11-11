#include "argon2_id.h"
#include "argon2_common.h"

static const frostrig_argon2_params argon2id_params = {
	.type     = Argon2_id,
	.t_cost   = FROSTRIG_ARGON2_ID_T_COST,
	.m_cost   = 512u, /* KiB */
};

frostrig_argon2id_ctx *frostrig_argon2id_create(void)
{
	return (frostrig_argon2id_ctx *)frostrig_argon2_ctx_create(&argon2id_params);
}

void frostrig_argon2id_destroy(frostrig_argon2id_ctx *ctx)
{
	frostrig_argon2_ctx_destroy((frostrig_argon2_ctx *)ctx);
}

int frostrig_argon2id_prepare(frostrig_argon2id_ctx *ctx, const void *key, size_t key_size)
{
	return frostrig_argon2_ctx_prepare((frostrig_argon2_ctx *)ctx, key, key_size);
}

int frostrig_argon2id_hash(frostrig_argon2id_ctx *ctx, const void *input, size_t input_size, void *output)
{
	return frostrig_argon2_ctx_hash((frostrig_argon2_ctx *)ctx, input, input_size, output);
}
