/*
 * C++ core extracted from VerusCoin's crypto/verus_hash.cpp.
 *
 * Implements CVerusHashV2::Hash, Write, init, and the static
 * function pointers.  Also provides CVerusHashV2_Init (extern "C")
 * used by verushash.cpp to set up the Haraka function pointers
 * before any CVerusHashV2 instance is constructed.
 */
#include "vh_stubs.h"
#include "haraka_portable.h"

#include <string.h>
#include <assert.h>

void (*CVerusHashV2::haraka512Function)(unsigned char *, const unsigned char *);
void (*CVerusHashV2::haraka512KeyedFunction)(unsigned char *, const unsigned char *, const u128 *);
void (*CVerusHashV2::haraka256Function)(unsigned char *, const unsigned char *);

void CVerusHashV2::init()
{
    load_constants_port();
    haraka512Function    = &haraka512_port;
    haraka512KeyedFunction = &haraka512_port_keyed;
    haraka256Function    = &haraka256_port;
}

extern "C" void CVerusHashV2_Init(int solutionVersion)
{
    (void)solutionVersion;
    CVerusHashV2::init();
}

/* ---------------------------------------------------------------- */
/*  CVerusHashV2::Hash                                               */
/* ---------------------------------------------------------------- */
void CVerusHashV2::Hash(void *result, const void *data, size_t len)
{
    unsigned char buf[128];
    unsigned char *bufPtr  = buf;
    int pos = 0, nextOffset = 64;
    unsigned char *bufPtr2 = bufPtr + nextOffset;
    unsigned char *ptr     = (unsigned char *)data;

    memset(bufPtr, 0, 32);

    for (; pos < (int)len; pos += 32)
    {
        if (len - pos >= 32) {
            memcpy(bufPtr + 32, ptr + pos, 32);
        } else {
            int i = (int)(len - pos);
            memcpy(bufPtr + 32, ptr + pos, i);
            memset(bufPtr + 32 + i, 0, 32 - i);
        }
        (*haraka512Function)(bufPtr2, bufPtr);
        bufPtr2  = bufPtr;
        bufPtr  += nextOffset;
        nextOffset *= -1;
    }
    memcpy(result, bufPtr, 32);
}

/* ---------------------------------------------------------------- */
/*  CVerusHashV2::Write                                              */
/* ---------------------------------------------------------------- */
CVerusHashV2 &CVerusHashV2::Write(const unsigned char *data, size_t len)
{
    unsigned char *tmp;
    for (int pos = 0; pos < (int)len;)
    {
        int room = 32 - curPos;
        if (len - pos >= (size_t)room)
        {
            memcpy(curBuf + 32 + curPos, data + pos, room);
            (*haraka512Function)(result, curBuf);
            tmp = curBuf;
            curBuf = result;
            result = tmp;
            pos += room;
            curPos = 0;
        }
        else
        {
            memcpy(curBuf + 32 + curPos, data + pos, len - pos);
            curPos += (int)(len - pos);
            pos = (int)len;
        }
    }
    return *this;
}
