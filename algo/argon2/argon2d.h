#ifndef FROSTRIG_ARGON2D_H
#define FROSTRIG_ARGON2D_H

#include <stddef.h>
#include <stdint.h>

#define FROSTRIG_ARGON2D_VARIANT_16000  9
#define FROSTRIG_ARGON2D_VARIANT_1000   10

typedef struct frostrig_argon2d16000_ctx frostrig_argon2d16000_ctx;
typedef struct frostrig_argon2d1000_ctx  frostrig_argon2d1000_ctx;

/* Argon2d, m_cost = 16000 KiB (~16 MiB) */
frostrig_argon2d16000_ctx *frostrig_argon2d16000_create(void);
void                       frostrig_argon2d16000_destroy(frostrig_argon2d16000_ctx *ctx);
int                        frostrig_argon2d16000_prepare(frostrig_argon2d16000_ctx *ctx, const void *key, size_t key_size);
int                        frostrig_argon2d16000_hash(frostrig_argon2d16000_ctx *ctx, const void *input, size_t input_size, void *output);

/* Argon2d, m_cost = 1000 KiB (~1 MiB) */
frostrig_argon2d1000_ctx  *frostrig_argon2d1000_create(void);
void                       frostrig_argon2d1000_destroy(frostrig_argon2d1000_ctx *ctx);
int                        frostrig_argon2d1000_prepare(frostrig_argon2d1000_ctx *ctx, const void *key, size_t key_size);
int                        frostrig_argon2d1000_hash(frostrig_argon2d1000_ctx *ctx, const void *input, size_t input_size, void *output);

#endif
