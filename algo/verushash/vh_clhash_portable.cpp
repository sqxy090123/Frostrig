/*
 * Standalone copy of VerusCoin's verus_clhash_portable.cpp.
 *
 * Only the functions required by CVerusHashV2's Finalize2b path are kept:
 *   - all SSE-emulation primitives
 *   - __verusclmulwithoutreduction64alignedrepeat{,_sv2_1,_sv2_2}_port
 *   - verusclhash{,_sv2_1,_sv2_2}_port
 *   - thread_local key/descr buffers
 *   - alloc_aligned_buffer
 *
 * mine_verus_v2_port is excluded (requires CBlockHeader / hash.h / block.h).
 */
#include "vh_stubs.h"
#include "haraka_portable.h"

#include <assert.h>
#include <string.h>
#if defined(_WIN32)
#include <malloc.h>
typedef unsigned char u_char;
#endif

int __cpuverusoptimized = 0x80;

thread_local thread_specific_ptr verusclhasher_key;
thread_local thread_specific_ptr verusclhasher_descr;

void *alloc_aligned_buffer(uint64_t bufSize)
{
    void *answer = NULL;
#if defined(_WIN32)
    answer = _aligned_malloc(bufSize, 16);
    if (!answer) return NULL;
#else
    if (posix_memalign(&answer, 16, bufSize))
        return NULL;
#endif
    return answer;
}

void clmul64(uint64_t a, uint64_t b, uint64_t *r)
{
    uint8_t s = 4, i;
    uint64_t two_s = 1 << s;
    uint64_t smask = two_s - 1;
    uint64_t u[16];
    uint64_t tmp;
    uint64_t ifmask;
    u[0] = 0;
    u[1] = b;
    for (i = 2; i < two_s; i += 2) {
        u[i]     = u[i >> 1] << 1;
        u[i + 1] = u[i] ^ b;
    }
    r[0] = u[a & smask];
    r[1] = 0;
    for (i = s; i < 64; i += s) {
        tmp = u[a >> i & smask];
        r[0] ^= tmp << i;
        r[1] ^= tmp >> (64 - i);
    }
    uint64_t m = 0xEEEEEEEEEEEEEEEE;
    for (i = 1; i < s; i++) {
        tmp    = ((a & m) >> i);
        m     &= m << 1;
        ifmask = -((b >> (64 - i)) & 1);
        r[1]  ^= (tmp & ifmask);
    }
}

u128 _mm_clmulepi64_si128_emu(const __m128i &a, const __m128i &b, int imm)
{
    uint64_t result[2];
    clmul64(*((uint64_t *)&a + (imm & 1)), *((uint64_t *)&b + ((imm & 0x10) >> 4)), result);
    return *(__m128i *)result;
}

u128 _mm_mulhrs_epi16_emu(__m128i _a, __m128i _b)
{
    int16_t result[8];
    int16_t *a = (int16_t *)&_a, *b = (int16_t *)&_b;
    for (int i = 0; i < 8; i++)
        result[i] = (int16_t)((((int32_t)(a[i]) * (int32_t)(b[i])) + 0x4000) >> 15);
    return *(__m128i *)result;
}

inline u128 _mm_set_epi64x_emu(uint64_t hi, uint64_t lo)
{
    __m128i result;
    ((uint64_t *)&result)[0] = lo;
    ((uint64_t *)&result)[1] = hi;
    return result;
}

inline u128 _mm_cvtsi64_si128_emu(uint64_t lo)
{
    __m128i result;
    ((uint64_t *)&result)[0] = lo;
    ((uint64_t *)&result)[1] = 0;
    return result;
}

inline int64_t _mm_cvtsi128_si64_emu(const __m128i &a)
{
    return *(const int64_t *)&a;
}

inline int32_t _mm_cvtsi128_si32_emu(const __m128i &a)
{
    return *(const int32_t *)&a;
}

inline u128 _mm_cvtsi32_si128_emu(uint32_t lo)
{
    __m128i result;
    ((uint32_t *)&result)[0] = lo;
    ((uint32_t *)&result)[1] = 0;
    ((uint64_t *)&result)[1] = 0;
    return result;
}

u128 _mm_setr_epi8_emu(u_char c0, u_char c1, u_char c2, u_char c3,
                       u_char c4, u_char c5, u_char c6, u_char c7,
                       u_char c8, u_char c9, u_char c10, u_char c11,
                       u_char c12, u_char c13, u_char c14, u_char c15)
{
    __m128i result;
    ((uint8_t *)&result)[0]  = c0;  ((uint8_t *)&result)[1]  = c1;
    ((uint8_t *)&result)[2]  = c2;  ((uint8_t *)&result)[3]  = c3;
    ((uint8_t *)&result)[4]  = c4;  ((uint8_t *)&result)[5]  = c5;
    ((uint8_t *)&result)[6]  = c6;  ((uint8_t *)&result)[7]  = c7;
    ((uint8_t *)&result)[8]  = c8;  ((uint8_t *)&result)[9]  = c9;
    ((uint8_t *)&result)[10] = c10; ((uint8_t *)&result)[11] = c11;
    ((uint8_t *)&result)[12] = c12; ((uint8_t *)&result)[13] = c13;
    ((uint8_t *)&result)[14] = c14; ((uint8_t *)&result)[15] = c15;
    return result;
}

inline __m128i _mm_srli_si128_emu(__m128i a, int imm8)
{
    unsigned char result[16];
    uint8_t shift = imm8 & 0xff;
    if (shift > 15) shift = 16;
    for (int i = 0; i < (16 - shift); i++)
        result[i] = ((unsigned char *)&a)[shift + i];
    for (int i = (16 - shift); i < 16; i++)
        result[i] = 0;
    return *(__m128i *)result;
}

inline __m128i _mm_xor_si128_emu(__m128i a, __m128i b)
{
#ifdef _WIN32
    uint64_t result[2];
    result[0] = *(uint64_t *)&a ^ *(uint64_t *)&b;
    result[1] = *((uint64_t *)&a + 1) ^ *((uint64_t *)&b + 1);
    return *(__m128i *)result;
#else
    return a ^ b;
#endif
}

inline __m128i _mm_load_si128_emu(const void *p)
{
    return *(__m128i *)p;
}

inline void _mm_store_si128_emu(void *p, __m128i val)
{
    *(__m128i *)p = val;
}

__m128i _mm_shuffle_epi8_emu(__m128i a, __m128i b)
{
    __m128i result;
    for (int i = 0; i < 16; i++)
        if (((uint8_t *)&b)[i] & 0x80)
            ((uint8_t *)&result)[i] = 0;
        else
            ((uint8_t *)&result)[i] = ((uint8_t *)&a)[((uint8_t *)&b)[i] & 0xf];
    return result;
}

static inline __m128i lazyLengthHash_port(uint64_t keylength, uint64_t length)
{
    const __m128i lengthvector = _mm_set_epi64x_emu(keylength, length);
    return _mm_clmulepi64_si128_emu(lengthvector, lengthvector, 0x10);
}

static inline __m128i precompReduction64_si128_port(__m128i A)
{
    const __m128i C = _mm_cvtsi64_si128_emu((1U << 4) + (1U << 3) + (1U << 1) + (1U << 0));
    __m128i Q2 = _mm_clmulepi64_si128_emu(A, C, 0x01);
    __m128i Q3 = _mm_shuffle_epi8_emu(
        _mm_setr_epi8_emu(0, 27, 54, 45, 108, 119, 90, 65,
                          (char)216, (char)195, (char)238, (char)245,
                          (char)180, (char)175, (char)130, (char)153),
        _mm_srli_si128_emu(Q2, 8));
    __m128i Q4    = _mm_xor_si128_emu(Q2, A);
    const __m128i final = _mm_xor_si128_emu(Q3, Q4);
    return final;
}

static inline uint64_t precompReduction64_port(__m128i A)
{
    __m128i tmp = precompReduction64_si128_port(A);
    return _mm_cvtsi128_si64_emu(tmp);
}

/* ---------------------------------------------------------------- */
/*  __verusclmulwithoutreduction64alignedrepeat_port                 */
/* ---------------------------------------------------------------- */
__m128i __verusclmulwithoutreduction64alignedrepeat_port(
    __m128i *randomsource, const __m128i buf[4], uint64_t keyMask,
    __m128i **pMoveScratch)
{
    __m128i const *pbuf;
    keyMask >>= 4;
    __m128i acc = _mm_load_si128_emu(randomsource + (keyMask + 2));

    for (int64_t i = 0; i < 32; i++)
    {
        const uint64_t selector = _mm_cvtsi128_si64_emu(acc);
        __m128i *prand    = randomsource + ((selector >> 5) & keyMask);
        __m128i *prandex  = randomsource + ((selector >> 32) & keyMask);
        *pMoveScratch++   = prand;
        *pMoveScratch++   = prandex;
        pbuf = buf + (selector & 3);

        switch (selector & 0x1c)
        {
            case 0:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf);
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 4:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i clprod2 = _mm_clmulepi64_si128_emu(temp2, temp2, 0x10);
                acc = _mm_xor_si128_emu(clprod2, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                acc = _mm_xor_si128_emu(add12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prand, tempb2);
                break;
            }
            case 8:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                acc = _mm_xor_si128_emu(add1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                acc = _mm_xor_si128_emu(clprod22, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 0xc:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const int32_t divisor = (uint32_t)selector;
                acc = _mm_xor_si128_emu(add1, acc);
                const int64_t dividend = _mm_cvtsi128_si64_emu(acc);
                const __m128i modulo   = _mm_cvtsi32_si128_emu(dividend % divisor);
                acc = _mm_xor_si128_emu(modulo, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                if (dividend & 1) {
                    const __m128i temp12 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    const __m128i temp22 = _mm_load_si128_emu(pbuf);
                    const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                    const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                    acc = _mm_xor_si128_emu(clprod12, acc);
                    const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                    acc = _mm_xor_si128_emu(clprod22, acc);
                    const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                    const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                    _mm_store_si128_emu(prand, tempb2);
                } else {
                    const __m128i tempb3 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    _mm_store_si128_emu(prand, tempb3);
                }
                break;
            }
            case 0x10:
            {
                const __m128i *rc = prand;
                __m128i tmp;
                __m128i temp1 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                __m128i  temp2 = _mm_load_si128_emu(pbuf);
                AES2_EMU(temp1, temp2, 0);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 4);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 8);  MIX2_EMU(temp1, temp2);
                acc = _mm_xor_si128_emu(temp1, acc);
                acc = _mm_xor_si128_emu(temp2, acc);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x14:
            {
                const __m128i *buftmp = pbuf - (((selector & 1) << 1) - 1);
                __m128i tmp;
                uint64_t rounds   = selector >> 61;
                __m128i *rc      = prand;
                uint64_t aesround = 0;
                __m128i onekey;
                do {
                    if (selector & ((0x10000000ull << rounds))) {
                        onekey = _mm_load_si128_emu(rc++);
                        const __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? pbuf : buftmp);
                        const __m128i add1  = _mm_xor_si128_emu(onekey, temp2);
                        const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                        acc = _mm_xor_si128_emu(clprod1, acc);
                    } else {
                        onekey = _mm_load_si128_emu(rc++);
                        __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? buftmp : pbuf);
                        const uint64_t roundidx = aesround++ << 2;
                        AES2_EMU(onekey, temp2, roundidx);
                        MIX2_EMU(onekey, temp2);
                        acc = _mm_xor_si128_emu(onekey, acc);
                        acc = _mm_xor_si128_emu(temp2, acc);
                    }
                } while (rounds--);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x18:
            {
                const __m128i temp1 = _mm_load_si128_emu(pbuf);
                const __m128i temp2 = _mm_load_si128_emu(prandex);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp2);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp2);
                const __m128i tempa3 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                acc = _mm_xor_si128_emu(tempa3, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, tempa3);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, tempa3);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 0x1c:
            {
                const __m128i temp1 = _mm_load_si128_emu(pbuf);
                const __m128i temp2 = _mm_load_si128_emu(prandex);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp2);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp2);
                const __m128i tempa3 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                acc = _mm_xor_si128_emu(tempa3, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, tempa3);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, tempa3);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
        }
    }
    return acc;
}

/* ---------------------------------------------------------------- */
/*  __verusclmulwithoutreduction64alignedrepeat_sv2_1_port           */
/* ---------------------------------------------------------------- */
__m128i __verusclmulwithoutreduction64alignedrepeat_sv2_1_port(
    __m128i *randomsource, const __m128i buf[4], uint64_t keyMask,
    __m128i **pMoveScratch)
{
    const __m128i pbuf_copy[4] = {
        _mm_xor_si128(buf[0], buf[2]), _mm_xor_si128(buf[1], buf[3]), buf[2], buf[3]};
    const __m128i *pbuf;
    keyMask >>= 4;
    __m128i acc = _mm_load_si128_emu(randomsource + (keyMask + 2));

    for (int64_t i = 0; i < 32; i++)
    {
        const uint64_t selector = _mm_cvtsi128_si64_emu(acc);
        __m128i *prand  = randomsource + ((selector >> 5) & keyMask);
        __m128i *prandex = randomsource + ((selector >> 32) & keyMask);
        *pMoveScratch++  = prand;
        *pMoveScratch++  = prandex;
        pbuf = pbuf_copy + (selector & 3);

        switch (selector & 0x1c)
        {
            case 0:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf);
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 4:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i clprod2 = _mm_clmulepi64_si128_emu(temp2, temp2, 0x10);
                acc = _mm_xor_si128_emu(clprod2, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                acc = _mm_xor_si128_emu(add12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prand, tempb2);
                break;
            }
            case 8:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                acc = _mm_xor_si128_emu(add1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                acc = _mm_xor_si128_emu(clprod22, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 0xc:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const int32_t divisor = (uint32_t)selector;
                acc = _mm_xor_si128_emu(add1, acc);
                const int64_t dividend = _mm_cvtsi128_si64_emu(acc);
                const __m128i modulo   = _mm_cvtsi32_si128_emu(dividend % divisor);
                acc = _mm_xor_si128_emu(modulo, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                if (dividend & 1) {
                    const __m128i temp12 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    const __m128i temp22 = _mm_load_si128_emu(pbuf);
                    const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                    const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                    acc = _mm_xor_si128_emu(clprod12, acc);
                    const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                    acc = _mm_xor_si128_emu(clprod22, acc);
                    const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                    const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                    _mm_store_si128_emu(prand, tempb2);
                } else {
                    const __m128i tempb3 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    _mm_store_si128_emu(prand, tempb3);
                }
                break;
            }
            case 0x10:
            {
                const __m128i *rc = prand;
                __m128i tmp;
                __m128i temp1 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                __m128i  temp2 = _mm_load_si128_emu(pbuf);
                AES2_EMU(temp1, temp2, 0);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 4);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 8);  MIX2_EMU(temp1, temp2);
                acc = _mm_xor_si128_emu(temp1, acc);
                acc = _mm_xor_si128_emu(temp2, acc);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x14:
            {
                const __m128i *buftmp = pbuf - (((selector & 1) << 1) - 1);
                __m128i tmp;
                uint64_t rounds   = selector >> 61;
                __m128i *rc       = prand;
                uint64_t aesround = 0;
                __m128i onekey;
                do {
                    if (selector & ((0x10000000ull << rounds))) {
                        onekey = _mm_load_si128_emu(rc++);
                        const __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? pbuf : buftmp);
                        const __m128i add1  = _mm_xor_si128_emu(onekey, temp2);
                        const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                        acc = _mm_xor_si128_emu(clprod1, acc);
                    } else {
                        onekey = _mm_load_si128_emu(rc++);
                        __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? buftmp : pbuf);
                        const uint64_t roundidx = aesround++ << 2;
                        AES2_EMU(onekey, temp2, roundidx);
                        MIX2_EMU(onekey, temp2);
                        acc = _mm_xor_si128_emu(onekey, acc);
                        acc = _mm_xor_si128_emu(temp2, acc);
                    }
                } while (rounds--);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x18:
            {
                const __m128i *buftmp = pbuf - (((selector & 1) << 1) - 1);
                __m128i tmp;
                uint64_t rounds   = selector >> 61;
                __m128i *rc       = prand;
                __m128i onekey;
                do {
                    if (selector & ((0x10000000ull << rounds))) {
                        onekey = _mm_load_si128_emu(rc++);
                        const __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? pbuf : buftmp);
                        const __m128i add1  = _mm_xor_si128_emu(onekey, temp2);
                        const int32_t divisor = (uint32_t)selector;
                        const int64_t dividend = _mm_cvtsi128_si64_emu(add1);
                        const __m128i modulo   = _mm_cvtsi32_si128_emu(dividend % divisor);
                        acc = _mm_xor_si128_emu(modulo, acc);
                    } else {
                        onekey = _mm_load_si128_emu(rc++);
                        __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? buftmp : pbuf);
                        const __m128i add1   = _mm_xor_si128_emu(onekey, temp2);
                        const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                        const __m128i clprod2 = _mm_mulhrs_epi16_emu(acc, clprod1);
                        acc = _mm_xor_si128_emu(clprod2, acc);
                    }
                } while (rounds--);
                const __m128i tempa3 = _mm_load_si128_emu(prandex);
                const __m128i tempa4 = _mm_xor_si128_emu(tempa3, acc);
                _mm_store_si128_emu(prandex, tempa4);
                _mm_store_si128_emu(prand, onekey);
                break;
            }
            case 0x1c:
            {
                const __m128i temp1 = _mm_load_si128_emu(pbuf);
                const __m128i temp2 = _mm_load_si128_emu(prandex);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp2);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp2);
                const __m128i tempa3 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                acc = _mm_xor_si128_emu(tempa3, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, tempa3);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, tempa3);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
        }
    }
    return acc;
}

/* ---------------------------------------------------------------- */
/*  __verusclmulwithoutreduction64alignedrepeat_sv2_2_port           */
/* ---------------------------------------------------------------- */
__m128i __verusclmulwithoutreduction64alignedrepeat_sv2_2_port(
    __m128i *randomsource, const __m128i buf[4], uint64_t keyMask,
    __m128i **pMoveScratch)
{
    const __m128i pbuf_copy[4] = {
        _mm_xor_si128(buf[0], buf[2]), _mm_xor_si128(buf[1], buf[3]), buf[2], buf[3]};
    const __m128i *pbuf;
    keyMask >>= 4;
    __m128i acc = _mm_load_si128_emu(randomsource + (keyMask + 2));

    for (int64_t i = 0; i < 32; i++)
    {
        const uint64_t selector = _mm_cvtsi128_si64_emu(acc);
        __m128i *prand  = randomsource + ((selector >> 5) & keyMask);
        __m128i *prandex = randomsource + ((selector >> 32) & keyMask);
        *pMoveScratch++  = prand;
        *pMoveScratch++  = prandex;
        pbuf = pbuf_copy + (selector & 3);

        switch (selector & 0x1c)
        {
            case 0:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf);
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 4:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i clprod2 = _mm_clmulepi64_si128_emu(temp2, temp2, 0x10);
                acc = _mm_xor_si128_emu(clprod2, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                acc = _mm_xor_si128_emu(add12, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prand, tempb2);
                break;
            }
            case 8:
            {
                const __m128i temp1 = _mm_load_si128_emu(prandex);
                const __m128i temp2 = _mm_load_si128_emu(pbuf);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                acc = _mm_xor_si128_emu(add1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                const __m128i temp12 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                const __m128i temp22 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                acc = _mm_xor_si128_emu(clprod12, acc);
                const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                acc = _mm_xor_si128_emu(clprod22, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
            case 0xc:
            {
                const __m128i temp1 = _mm_load_si128_emu(prand);
                const __m128i temp2 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const int32_t divisor = (uint32_t)selector;
                acc = _mm_xor_si128_emu(add1, acc);
                const int64_t dividend = _mm_cvtsi128_si64_emu(acc);
                const __m128i modulo   = _mm_cvtsi32_si128_emu(dividend % divisor);
                acc = _mm_xor_si128_emu(modulo, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp1);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp1);
                if (dividend & 1) {
                    const __m128i temp12 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    const __m128i temp22 = _mm_load_si128_emu(pbuf);
                    const __m128i add12  = _mm_xor_si128_emu(temp12, temp22);
                    const __m128i clprod12 = _mm_clmulepi64_si128_emu(add12, add12, 0x10);
                    acc = _mm_xor_si128_emu(clprod12, acc);
                    const __m128i clprod22 = _mm_clmulepi64_si128_emu(temp22, temp22, 0x10);
                    acc = _mm_xor_si128_emu(clprod22, acc);
                    const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, temp12);
                    const __m128i tempb2 = _mm_xor_si128_emu(tempb1, temp12);
                    _mm_store_si128_emu(prand, tempb2);
                } else {
                    const __m128i tempb3 = _mm_load_si128_emu(prandex);
                    _mm_store_si128_emu(prandex, tempa2);
                    _mm_store_si128_emu(prand, tempb3);
                    const __m128i tempb4 = _mm_load_si128_emu(pbuf);
                    acc = _mm_xor_si128_emu(tempb4, acc);
                }
                break;
            }
            case 0x10:
            {
                const __m128i *rc = prand;
                __m128i tmp;
                __m128i temp1 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                __m128i  temp2 = _mm_load_si128_emu(pbuf);
                AES2_EMU(temp1, temp2, 0);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 4);  MIX2_EMU(temp1, temp2);
                AES2_EMU(temp1, temp2, 8);  MIX2_EMU(temp1, temp2);
                acc = _mm_xor_si128_emu(temp1, acc);
                acc = _mm_xor_si128_emu(temp2, acc);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x14:
            {
                const __m128i *buftmp = pbuf - (((selector & 1) << 1) - 1);
                __m128i tmp;
                uint64_t rounds   = selector >> 61;
                __m128i *rc       = prand;
                uint64_t aesround = 0;
                __m128i onekey;
                do {
                    if (selector & ((0x10000000ull << rounds))) {
                        onekey = _mm_load_si128_emu(rc++);
                        const __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? pbuf : buftmp);
                        const __m128i add1  = _mm_xor_si128_emu(onekey, temp2);
                        const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                        acc = _mm_xor_si128_emu(clprod1, acc);
                    } else {
                        onekey = _mm_load_si128_emu(rc++);
                        __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? buftmp : pbuf);
                        const uint64_t roundidx = aesround++ << 2;
                        AES2_EMU(onekey, temp2, roundidx);
                        MIX2_EMU(onekey, temp2);
                        acc = _mm_xor_si128_emu(onekey, acc);
                        acc = _mm_xor_si128_emu(temp2, acc);
                    }
                } while (rounds--);
                const __m128i tempa1 = _mm_load_si128_emu(prand);
                const __m128i tempa2 = _mm_mulhrs_epi16_emu(acc, tempa1);
                const __m128i tempa3 = _mm_xor_si128_emu(tempa1, tempa2);
                const __m128i tempa4 = _mm_load_si128_emu(prandex);
                _mm_store_si128_emu(prandex, tempa3);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x18:
            {
                const __m128i *buftmp = pbuf - (((selector & 1) << 1) - 1);
                __m128i tmp;
                uint64_t rounds   = selector >> 61;
                __m128i *rc       = prand;
                __m128i onekey;
                do {
                    if (selector & ((0x10000000ull << rounds))) {
                        onekey = _mm_load_si128_emu(rc++);
                        const __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? pbuf : buftmp);
                        onekey = _mm_xor_si128_emu(onekey, temp2);
                        const int32_t divisor = (uint32_t)selector;
                        const int64_t dividend = _mm_cvtsi128_si64_emu(onekey);
                        const __m128i modulo   = _mm_cvtsi32_si128_emu(dividend % divisor);
                        acc = _mm_xor_si128_emu(modulo, acc);
                    } else {
                        onekey = _mm_load_si128_emu(rc++);
                        __m128i temp2 = _mm_load_si128_emu(rounds & 1 ? buftmp : pbuf);
                        onekey = _mm_xor_si128_emu(onekey, temp2);
                        onekey = _mm_clmulepi64_si128_emu(onekey, onekey, 0x10);
                        const __m128i clprod2 = _mm_mulhrs_epi16_emu(acc, onekey);
                        acc = _mm_xor_si128_emu(clprod2, acc);
                    }
                } while (rounds--);
                const __m128i tempa3 = _mm_load_si128_emu(prandex);
                const __m128i tempa4 = _mm_xor_si128_emu(tempa3, acc);
                _mm_store_si128_emu(prandex, onekey);
                _mm_store_si128_emu(prand, tempa4);
                break;
            }
            case 0x1c:
            {
                const __m128i temp1 = _mm_load_si128_emu(pbuf);
                const __m128i temp2 = _mm_load_si128_emu(prandex);
                const __m128i add1  = _mm_xor_si128_emu(temp1, temp2);
                const __m128i clprod1 = _mm_clmulepi64_si128_emu(add1, add1, 0x10);
                acc = _mm_xor_si128_emu(clprod1, acc);
                const __m128i tempa1 = _mm_mulhrs_epi16_emu(acc, temp2);
                const __m128i tempa2 = _mm_xor_si128_emu(tempa1, temp2);
                const __m128i tempa3 = _mm_load_si128_emu(prand);
                _mm_store_si128_emu(prand, tempa2);
                acc = _mm_xor_si128_emu(tempa3, acc);
                const __m128i temp4 = _mm_load_si128_emu(pbuf - (((selector & 1) << 1) - 1));
                acc = _mm_xor_si128_emu(temp4, acc);
                const __m128i tempb1 = _mm_mulhrs_epi16_emu(acc, tempa3);
                const __m128i tempb2 = _mm_xor_si128_emu(tempb1, tempa3);
                _mm_store_si128_emu(prandex, tempb2);
                break;
            }
        }
    }
    return acc;
}

/* ---------------------------------------------------------------- */
/*  verusclhash_{port, sv2_1_port, sv2_2_port}                      */
/* ---------------------------------------------------------------- */
uint64_t verusclhash_port(void *random, const unsigned char buf[64],
                          uint64_t keyMask, __m128i **pMoveScratch)
{
    __m128i *rs64 = (__m128i *)random;
    const __m128i *string = (const __m128i *)buf;
    __m128i acc = __verusclmulwithoutreduction64alignedrepeat_port(rs64, string, keyMask, pMoveScratch);
    acc = _mm_xor_si128_emu(acc, lazyLengthHash_port(1024, 64));
    return precompReduction64_port(acc);
}

uint64_t verusclhash_sv2_1_port(void *random, const unsigned char buf[64],
                                uint64_t keyMask, __m128i **pMoveScratch)
{
    __m128i *rs64 = (__m128i *)random;
    const __m128i *string = (const __m128i *)buf;
    __m128i acc = __verusclmulwithoutreduction64alignedrepeat_sv2_1_port(rs64, string, keyMask, pMoveScratch);
    acc = _mm_xor_si128_emu(acc, lazyLengthHash_port(1024, 64));
    return precompReduction64_port(acc);
}

uint64_t verusclhash_sv2_2_port(void *random, const unsigned char buf[64],
                                uint64_t keyMask, __m128i **pMoveScratch)
{
    __m128i *rs64 = (__m128i *)random;
    const __m128i *string = (const __m128i *)buf;
    __m128i acc = __verusclmulwithoutreduction64alignedrepeat_sv2_2_port(rs64, string, keyMask, pMoveScratch);
    acc = _mm_xor_si128_emu(acc, lazyLengthHash_port(1024, 64));
    return precompReduction64_port(acc);
}
