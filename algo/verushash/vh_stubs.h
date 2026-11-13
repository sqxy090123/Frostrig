#ifndef FROSTRIG_VH_STUBS_H
#define FROSTRIG_VH_STUBS_H

/*
 * Minimal stubs that replace the VerusCoin project-wide headers
 * (boost/thread.hpp, tinyformat.h, uint256.h, hash.h, primitives/block.h)
 * so that the VerusHash C++ core can compile standalone in frostrig.
 *
 * u128 is defined here (matching the __m128i type used by Haraka/clhash)
 * so that both vh_clhash_portable.cpp and vh_hash.cpp can reference it
 * without pulling in haraka_portable.h in the C++ context.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* SSE2 intrinsics for x86; SSE2NEON provides the same symbols on ARM. */
#if defined(__arm__) || defined(__aarch64__)
#define SSE2NEON_SUPPRESS_WARNINGS
#include "sse2neon.h"
#else
#include <immintrin.h>
#endif

/* Type alias matching the one in haraka_portable.h / haraka_portable.c */
typedef __m128i u128;

/* ---------------------------------------------------------------- */
/*  uint256 stub                                                     */
/* ---------------------------------------------------------------- */
class uint256 {
public:
    alignas(16) uint8_t data[32];

    uint256() { memset(data, 0, sizeof(data)); }
    uint256(const uint8_t *src) { memcpy(data, src, 32); }

    bool operator==(const uint256 &o) const { return memcmp(data, o.data, 32) == 0; }
    bool operator!=(const uint256 &o) const { return memcmp(data, o.data, 32) == 0; }
};

/* ---------------------------------------------------------------- */
/*  thread_specific_ptr  (replaces boost::thread_specific_ptr)       */
/* ---------------------------------------------------------------- */
struct thread_specific_ptr {
    void *ptr;
    thread_specific_ptr() : ptr(nullptr) {}
    ~thread_specific_ptr() { reset(); }
    void reset(void *newptr = nullptr) {
        if (ptr && ptr != newptr)
            free(ptr);
        ptr = newptr;
    }
    void *get() { return ptr; }
};

/* ---------------------------------------------------------------- */
/*  verusclhash_descr                                                */
/* ---------------------------------------------------------------- */
struct verusclhash_descr {
    uint256 seed;
    uint32_t keySizeInBytes;
};

/* ---------------------------------------------------------------- */
/*  extern globals declared in vh_clhash_portable.cpp                */
/* ---------------------------------------------------------------- */
extern thread_local thread_specific_ptr verusclhasher_key;
extern thread_local thread_specific_ptr verusclhasher_descr;
extern int __cpuverusoptimized;

/* ---------------------------------------------------------------- */
/*  VerusHash version constants                                       */
/* ---------------------------------------------------------------- */
#define FROSTRIG_VH_KEYSIZE  1024 * 8 + (40 * 16)
#define FROSTRIG_VH_SV2       1
#define FROSTRIG_VH_SV2_1     3
#define FROSTRIG_VH_SV2_2     4

/* ---------------------------------------------------------------- */
/*  C-level clhash function pointer types                            */
/* ---------------------------------------------------------------- */
typedef uint64_t (*verusclhash_fn)(void *, const unsigned char buf[64], uint64_t, u128 **);
typedef u128     (*verusclmul_fn)(u128 *, const u128[4], uint64_t, u128 **);

/* ---------------------------------------------------------------- */
/*  extern C declarations (implemented in vh_clhash_portable.cpp)    */
/* ---------------------------------------------------------------- */
extern "C" {
    void *alloc_aligned_buffer(uint64_t bufSize);

    uint64_t verusclhash_port(void *random, const unsigned char buf[64], uint64_t keyMask, u128 **pMoveScratch);
    uint64_t verusclhash_sv2_1_port(void *random, const unsigned char buf[64], uint64_t keyMask, u128 **pMoveScratch);
    uint64_t verusclhash_sv2_2_port(void *random, const unsigned char buf[64], uint64_t keyMask, u128 **pMoveScratch);

    u128 __verusclmulwithoutreduction64alignedrepeat_port(u128 *rs, const u128 buf[4], uint64_t keyMask, u128 **pMoveScratch);
    u128 __verusclmulwithoutreduction64alignedrepeat_sv2_1_port(u128 *rs, const u128 buf[4], uint64_t keyMask, u128 **pMoveScratch);
    u128 __verusclmulwithoutreduction64alignedrepeat_sv2_2_port(u128 *rs, const u128 buf[4], uint64_t keyMask, u128 **pMoveScratch);

    /* Haraka portable C functions (from haraka_portable.c) */
    void load_constants_port();
    void haraka512_port(unsigned char *out, const unsigned char *in);
    void haraka512_port_keyed(unsigned char *out, const unsigned char *in, const u128 *rc);
    void haraka256_port(unsigned char *out, const unsigned char *in);
}

/* ---------------------------------------------------------------- */
/*  C++ verusclhasher struct (minimal, from verus_clhash.h)         */
/* ---------------------------------------------------------------- */
struct verusclhasher {
    uint64_t keySizeInBytes;
    uint64_t keyMask;
    verusclhash_fn      verusclhashfunction;
    verusclmul_fn       verusinternalclhashfunction;

    static uint64_t keymask(uint64_t keysize) {
        int i = 0;
        while (keysize >>= 1) i++;
        return i ? (((uint64_t)1) << i) - 1 : 0;
    }

    verusclhasher(uint64_t keysize = FROSTRIG_VH_KEYSIZE, int solutionVersion = FROSTRIG_VH_SV2)
        : keySizeInBytes((keysize >> 5) << 5)
    {
        if (solutionVersion >= FROSTRIG_VH_SV2_2) {
            verusclhashfunction       = &verusclhash_sv2_2_port;
            verusinternalclhashfunction = &__verusclmulwithoutreduction64alignedrepeat_sv2_2_port;
        } else if (solutionVersion >= FROSTRIG_VH_SV2_1) {
            verusclhashfunction       = &verusclhash_sv2_1_port;
            verusinternalclhashfunction = &__verusclmulwithoutreduction64alignedrepeat_sv2_1_port;
        } else {
            verusclhashfunction       = &verusclhash_port;
            verusinternalclhashfunction = &__verusclmulwithoutreduction64alignedrepeat_port;
        }

        if (verusclhasher_key.get() &&
            keySizeInBytes != ((verusclhash_descr *)verusclhasher_descr.get())->keySizeInBytes)
        {
            verusclhasher_key.reset();
            verusclhasher_descr.reset();
        }

        void *key = nullptr;
        if (!(key = verusclhasher_key.get()) &&
            (verusclhasher_key.reset(alloc_aligned_buffer(keySizeInBytes << 1)),
             key = verusclhasher_key.get()))
        {
            verusclhash_descr *pdesc = nullptr;
            if (verusclhasher_descr.reset(alloc_aligned_buffer(sizeof(verusclhash_descr))),
                pdesc = (verusclhash_descr *)verusclhasher_descr.get())
            {
                pdesc->keySizeInBytes = keySizeInBytes;
                pdesc->seed = uint256{};
            } else {
                verusclhasher_key.reset();
                key = nullptr;
            }
        }
        keyMask = key ? keymask(keySizeInBytes) : 0;
        if (!key) keySizeInBytes = 0;
    }

    void *gethasherrefresh() {
        verusclhash_descr *pdesc = (verusclhash_descr *)verusclhasher_descr.get();
        return (unsigned char *)verusclhasher_key.get() + pdesc->keySizeInBytes;
    }

    u128 **getpmovescratch(void *hasherrefresh) {
        return (u128 **)((unsigned char *)hasherrefresh + keyrefreshsize());
    }

    verusclhash_descr *gethasherdescription() const {
        return (verusclhash_descr *)verusclhasher_descr.get();
    }

    uint64_t keyrefreshsize() const { return keyMask + 1; }

    void *fixupkey(void *hashKey, verusclhash_descr &desc) {
        unsigned char *ret = (unsigned char *)hashKey;
        uint32_t ofs = desc.keySizeInBytes >> 4;
        u128 **ppfixup = getpmovescratch(ret + desc.keySizeInBytes);
        for (u128 *pfixup = *ppfixup; pfixup; pfixup = *++ppfixup)
            *pfixup = *(pfixup + ofs);
        return hashKey;
    }

    void *gethashkey() {
        unsigned char *ret = (unsigned char *)verusclhasher_key.get();
        return fixupkey(ret, *(verusclhash_descr *)verusclhasher_descr.get());
    }

    uint64_t operator()(const unsigned char buf[64]) const {
        unsigned char *pkey = (unsigned char *)verusclhasher_key.get();
        verusclhash_descr *pdesc = (verusclhash_descr *)verusclhasher_descr.get();
        return (*verusclhashfunction)(pkey, buf, keyMask,
                                     (u128 **)(pkey + (pdesc->keySizeInBytes + keyrefreshsize())));
    }

    uint64_t operator()(const unsigned char buf[64], void *pkey) const {
        verusclhash_descr *pdesc = (verusclhash_descr *)verusclhasher_descr.get();
        return (*verusclhashfunction)(pkey, buf, keyMask,
                                      (u128 **)((unsigned char *)pkey + (pdesc->keySizeInBytes + keyrefreshsize())));
    }

    uint64_t operator()(const unsigned char buf[64], void *pkey, u128 **pMoveScratch) const {
        return (*verusclhashfunction)((unsigned char *)pkey, buf, keyMask, pMoveScratch);
    }
};

/* ---------------------------------------------------------------- */
/*  CVerusHashV2 (from verus_hash.h, stripped of debug output)      */
/* ---------------------------------------------------------------- */
class CVerusHashV2 {
public:
    static void (*haraka512Function)(unsigned char *, const unsigned char *);
    static void (*haraka512KeyedFunction)(unsigned char *, const unsigned char *, const u128 *);
    static void (*haraka256Function)(unsigned char *, const unsigned char *);
    static void init();

    verusclhasher vclh;

    CVerusHashV2(int solutionVersion = FROSTRIG_VH_SV2)
        : vclh(FROSTRIG_VH_KEYSIZE, solutionVersion)
    {
        if (!verusclhasher_key.get())
            abort();
    }

    static void Hash(void *result, const void *data, size_t len);

    CVerusHashV2 &Write(const unsigned char *data, size_t len);

    CVerusHashV2 &Reset() {
        curBuf = buf1;
        result = buf2;
        curPos = 0;
        memset(buf1, 0, sizeof(buf1));
        return *this;
    }

    int64_t *ExtraI64Ptr() { return (int64_t *)(curBuf + 32); }

    void ClearExtra() {
        if (curPos)
            memset(curBuf + 32 + curPos, 0, 32 - curPos);
    }

    void ExtraHash(unsigned char hash[32]) { (*haraka512Function)(hash, curBuf); }
    void ExtraHashKeyed(unsigned char hash[32], u128 *key) { (*haraka512KeyedFunction)(hash, curBuf, key); }

    void Finalize(unsigned char hash[32]) {
        if (curPos) {
            memset(curBuf + 32 + curPos, 0, 32 - curPos);
            (*haraka512Function)(hash, curBuf);
        } else {
            memcpy(hash, curBuf, 32);
        }
    }

    template <typename T>
    void FillExtra(const T *_data) {
        unsigned char *data = (unsigned char *)_data;
        int pos = curPos;
        int left = 32 - pos;
        do {
            int len = left > (int)sizeof(T) ? (int)sizeof(T) : left;
            memcpy(curBuf + 32 + pos, data, len);
            pos  += len;
            left -= len;
        } while (left > 0);
    }

    uint64_t IntermediateTo128Offset(uint64_t intermediate) {
        return intermediate & (vclh.keyMask >> 4);
    }

    void Finalize2b(unsigned char hash[32]) {
        FillExtra((u128 *)curBuf);

        u128 *key = GenNewCLKey(curBuf);

        uint64_t intermediate = vclh(curBuf, key);

        FillExtra(&intermediate);

        (*haraka512KeyedFunction)(hash, curBuf, key + IntermediateTo128Offset(intermediate));
    }

    static u128 *GenNewCLKey(unsigned char *seedBytes32) {
        unsigned char *key = (unsigned char *)verusclhasher_key.get();
        verusclhash_descr *pdesc = (verusclhash_descr *)verusclhasher_descr.get();
        int size = pdesc->keySizeInBytes;
        int refreshsize = verusclhasher::keymask(size) + 1;

        if (pdesc->seed != uint256(seedBytes32)) {
            int n256blks = size >> 5;
            int nbytesExtra = size & 0x1f;
            unsigned char *pkey = key;
            unsigned char *psrc = seedBytes32;
            for (int i = 0; i < n256blks; i++) {
                (*haraka256Function)(pkey, psrc);
                psrc = pkey;
                pkey += 32;
            }
            if (nbytesExtra) {
                unsigned char buf[32];
                (*haraka256Function)(buf, psrc);
                memcpy(pkey, buf, nbytesExtra);
            }
            pdesc->seed = uint256(seedBytes32);
            memcpy(key + size, key, refreshsize);
        } else {
            memcpy(key, key + size, refreshsize);
        }

        memset(key + (size + refreshsize), 0, size - refreshsize);
        return (u128 *)key;
    }

    unsigned char *CurBuffer() { return curBuf; }

private:
    alignas(32) unsigned char buf1[64] = {0}, buf2[64];
    unsigned char *curBuf = buf1, *result = buf2;
    size_t curPos = 0;
};

#endif /* FROSTRIG_VH_STUBS_H */
