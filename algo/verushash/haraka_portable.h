#ifndef FROSTRIG_HARAKA_PORTABLE_H
#define FROSTRIG_HARAKA_PORTABLE_H

/*
 * Standalone copy of haraka_portable.h from the VerusCoin project.
 * The SSE2NEON conditional include has been replaced by a direct
 * immintrin.h include so this file compiles on x86_64 without the
 * VerusCoin project's crypto/compat/ include layout.
 */

#include <immintrin.h>

#define NUMROUNDS 5

#ifdef _WIN32
typedef unsigned long long u64;
#else
typedef unsigned long u64;
#endif
typedef __m128i u128;

#ifdef __cplusplus
extern "C" {
#endif

extern void aesenc(unsigned char *s, const unsigned char *rk);

#define AES2_EMU(s0, s1, rci) \
  aesenc((unsigned char *)&s0, (unsigned char *)&(rc[rci])); \
  aesenc((unsigned char *)&s1, (unsigned char *)&(rc[rci + 1])); \
  aesenc((unsigned char *)&s0, (unsigned char *)&(rc[rci + 2])); \
  aesenc((unsigned char *)&s1, (unsigned char *)&(rc[rci + 3]));

typedef unsigned int uint32_t;

static inline __m128i _mm_unpacklo_epi32_emu(__m128i a, __m128i b)
{
    uint32_t result[4];
    uint32_t *tmp1 = (uint32_t *)&a, *tmp2 = (uint32_t *)&b;
    result[0] = tmp1[0];
    result[1] = tmp2[0];
    result[2] = tmp1[1];
    result[3] = tmp2[1];
    return *(__m128i *)result;
}

static inline __m128i _mm_unpackhi_epi32_emu(__m128i a, __m128i b)
{
    uint32_t result[4];
    uint32_t *tmp1 = (uint32_t *)&a, *tmp2 = (uint32_t *)&b;
    result[0] = tmp1[2];
    result[1] = tmp2[2];
    result[2] = tmp1[3];
    result[3] = tmp2[3];
    return *(__m128i *)result;
}

#define MIX2_EMU(s0, s1) \
  tmp = _mm_unpacklo_epi32_emu(s0, s1); \
  s1 = _mm_unpackhi_epi32_emu(s0, s1); \
  s0 = tmp;

void load_constants_port();
void tweak_constants(const unsigned char *pk_seed, const unsigned char *sk_seed,
                     unsigned long long seed_length);

void haraka_S(unsigned char *out, unsigned long long outlen,
               const unsigned char *in, unsigned long long inlen);

void haraka512_perm(unsigned char *out, const unsigned char *in);

void haraka512_port(unsigned char *out, const unsigned char *in);

void haraka512_port_keyed(unsigned char *out, const unsigned char *in, const u128 *rc);

void haraka512_perm_zero(unsigned char *out, const unsigned char *in);

void haraka512_port_zero(unsigned char *out, const unsigned char *in);

void haraka256_port(unsigned char *out, const unsigned char *in);

void haraka256_sk(unsigned char *out, const unsigned char *in);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* FROSTRIG_HARAKA_PORTABLE_H */
