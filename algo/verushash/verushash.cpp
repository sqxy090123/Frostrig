/*
 * frostrig algo module: verushash vh/2.2 and vh/3.1
 *
 * C++ core extracted from VerusCoin's crypto/verus_hash.cpp and
 * crypto/verus_clhash_portable.cpp, with all project-wide dependencies
 * (boost, tinyformat, uint256, hash.h, primitives/block.h) replaced by
 * the minimal stubs in vh_stubs.h.
 *
 * Compiled with:
 *   g++ -c -O2 -fPIC -std=c++11 -I. \
 *       vh_clhash_portable.cpp vh_hash.cpp
 *   gcc -c -O2 -fPIC haraka_portable.c verushash.c
 *
 * Links the _port variants of verusclhash; no ISA extension needed.
 */
#include "verushash.h"
#include "vh_stubs.h"

#include <stdlib.h>
#include <string.h>

/* C++ entry points implemented in vh_hash.cpp */
extern "C" {
void CVerusHashV2_Init(int solutionVersion);
}

/* ---------------------------------------------------------------- */
/*  Opaque context                                                   */
/* ---------------------------------------------------------------- */
struct frostrig_vh_ctx {
    CVerusHashV2 *state;
    int           solution_version;
};

static frostrig_vh_ctx *vh_ctx_new(int sv)
{
    CVerusHashV2_Init(sv);          /* set the static function pointers  */
    CVerusHashV2 *s = new CVerusHashV2(sv);
    frostrig_vh_ctx *c = (frostrig_vh_ctx *)calloc(1, sizeof(*c));
    if (c == NULL) { delete s; return NULL; }
    c->state = s;
    c->solution_version = sv;
    return c;
}

static void vh_ctx_del(frostrig_vh_ctx *c)
{
    if (c == NULL) return;
    delete c->state;
    free(c);
}

/* VerusHash is stateless between independent hash calls — prepare is a no-op. */
static int vh_ctx_prepare(frostrig_vh_ctx *c, const void *key, size_t key_size)
{
    (void)key; (void)key_size;
    return c != NULL ? 0 : -1;
}

static int vh_ctx_hash(frostrig_vh_ctx *c, const void *input, size_t input_size, void *output)
{
    if (c == NULL || c->state == NULL || input == NULL || output == NULL)
        return -1;

    c->state->Reset();
    c->state->Write((const unsigned char *)input, input_size);
    c->state->Finalize2b((unsigned char *)output);
    return 0;
}

extern "C" {

/* Force the linker to pull in vh_hash.o and vh_clhash_portable.o by
   referencing CVerusHashV2_Init (vh_hash.o) and alloc_aligned_buffer
   (vh_clhash_portable.o) through a C ABI entry point. */
void frostrig_vh_force_link(void)
{
    CVerusHashV2_Init(0);
    (void)alloc_aligned_buffer(16);
}

/* ---------------------------------------------------------------- */
/*  vh/2.2  (solutionVersion = FROSTRIG_VH_SV2_2 = 4)               */
/* ---------------------------------------------------------------- */
frostrig_vh_ctx *frostrig_verushash_v22_create(void)
{
    return vh_ctx_new(FROSTRIG_VH_SV2_2);
}
void frostrig_verushash_v22_destroy(frostrig_vh_ctx *c)
{
    vh_ctx_del(c);
}
int frostrig_verushash_v22_prepare(frostrig_vh_ctx *c, const void *key, size_t key_size)
{
    return vh_ctx_prepare(c, key, key_size);
}
int frostrig_verushash_v22_hash(frostrig_vh_ctx *c, const void *input, size_t input_size, void *output)
{
    return vh_ctx_hash(c, input, input_size, output);
}

/* ---------------------------------------------------------------- */
/*  vh/3.1  (solutionVersion = FROSTRIG_VH_SV2_1 = 3)               */
/* ---------------------------------------------------------------- */
frostrig_vh_ctx *frostrig_verushash_v31_create(void)
{
    return vh_ctx_new(FROSTRIG_VH_SV2_1);
}
void frostrig_verushash_v31_destroy(frostrig_vh_ctx *c)
{
    vh_ctx_del(c);
}
int frostrig_verushash_v31_prepare(frostrig_vh_ctx *c, const void *key, size_t key_size)
{
    return vh_ctx_prepare(c, key, key_size);
}
int frostrig_verushash_v31_hash(frostrig_vh_ctx *c, const void *input, size_t input_size, void *output)
{
    return vh_ctx_hash(c, input, input_size, output);
}

} /* extern "C" */
