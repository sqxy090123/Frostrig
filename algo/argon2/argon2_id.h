#ifndef FROSTRIG_ARGON2_ID_H
#define FROSTRIG_ARGON2_ID_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_ARGON2_VARIANT_ID 8

typedef struct frostrig_argon2id_ctx frostrig_argon2id_ctx;

frostrig_argon2id_ctx *frostrig_argon2id_create(void);
void                    frostrig_argon2id_destroy(frostrig_argon2id_ctx *ctx);
int                     frostrig_argon2id_prepare(frostrig_argon2id_ctx *ctx, const void *key, size_t key_size);
int                     frostrig_argon2id_hash(frostrig_argon2id_ctx *ctx, const void *input, size_t input_size, void *output);

#endif
