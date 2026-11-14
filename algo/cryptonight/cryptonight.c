/*
 * frostrig CryptoNight/8 C implementation
 *
 * Two variants:
 *   CN_PICO  - 256 KiB memory pool, classic CryptoNight/8 (no AES)
 *   CN_HEAVY - 4 MiB memory pool, CryptoNight/8 with AES-128-ECB
 *
 * The memory pool is seeded in prepare() via BLAKE2b(key || counter).
 * hash() runs one full CryptoNight/8 pass over the memory pool.
 *
 * Build (Linux):
 *   cc -O2 -fPIC -march=native -I third_party/argon2/include \
 *      -I third_party/argon2/src -I algo/cryptonight \
 *      algo/cryptonight/cryptonight.c \
 *      third_party/argon2/src/blake2b.c \
 *      -c -o algo/cryptonight/cryptonight.o
 */
#include "cryptonight.h"
#include <stdlib.h>
#include <string.h>

#include <blake2.h>

/* AES-NI */
#ifdef _MSC_VER
#include <nmmintrin.h>
#else
#include <wmmintrin.h>
#endif

#define CN_HASH_LEN 32
#define CN_OUT_LEN  32

/* Per-variant memory pool sizes (bytes) */
#define CN_PICO_MEM  (256 * 1024)
#define CN_HEAVY_MEM (4 * 1024 * 1024)

/* AES-128 key schedule */
static void cn_aes_key_expand(const uint8_t key[16], __m128i rounds[11])
{
	__m128i rk = _mm_load_si128((__m128i *)key);
	rounds[0] = rk;
	for (int i = 1; i <= 10; i++) {
		rk = _mm_aesenc_si128(rk, rounds[i - 1]);
		if (i < 10) {
			rounds[i] = rk;
		} else {
			rounds[i] = _mm_aesenclast_si128(rk, rounds[i - 1]);
		}
	}
}

typedef struct {
	uint8_t  *mem;
	size_t    mem_size;
	int       is_heavy;
	uint8_t   seed[32];
	int       prepared;
} cn_ctx;

/* --- Generic implementation --- */

static frostrig_cryptonight_ctx *cn_ctx_create(int is_heavy)
{
	cn_ctx *c = (cn_ctx *)calloc(1, sizeof(cn_ctx));
	if (c == NULL) {
		return NULL;
	}
	c->is_heavy = is_heavy;
	c->mem_size = is_heavy ? CN_HEAVY_MEM : CN_PICO_MEM;
	c->mem = (uint8_t *)calloc(1, c->mem_size);
	if (c->mem == NULL) {
		free(c);
		return NULL;
	}
	return (frostrig_cryptonight_ctx *)c;
}

static void cn_ctx_destroy(frostrig_cryptonight_ctx *h)
{
	if (h == NULL) {
		return;
	}
	cn_ctx *c = (cn_ctx *)h;
	free(c->mem);
	free(c);
}

static int cn_ctx_prepare(frostrig_cryptonight_ctx *h,
                          const void *key, size_t key_size)
{
	if (h == NULL) {
		return -1;
	}
	cn_ctx *c = (cn_ctx *)h;

	if (key == NULL || key_size == 0) {
		static const uint8_t zero[32];
		key = zero;
		key_size = 32;
	}

	memset(c->seed, 0, 32);
	memcpy(c->seed, key, key_size < 32 ? key_size : 32);

	for (size_t off = 0; off < c->mem_size; off += BLAKE2B_OUTBYTES) {
		uint8_t buf[48];
		memset(buf, 0, sizeof(buf));
		memcpy(buf, c->seed, 32);
		uint64_t idx = off / BLAKE2B_OUTBYTES;
		memcpy(buf + 32, &idx, 8);
		uint8_t out[BLAKE2B_OUTBYTES];
		blake2b(out, BLAKE2B_OUTBYTES, buf, 48, NULL, 0);
		memcpy(c->mem + off, out, BLAKE2B_OUTBYTES);
	}

	c->prepared = 1;
	return 0;
}

static int cn_ctx_hash(frostrig_cryptonight_ctx *h,
                      const void *input, size_t input_size,
                      void *output)
{
	if (h == NULL || input == NULL || output == NULL || input_size == 0) {
		return -1;
	}
	cn_ctx *c = (cn_ctx *)h;

	uint8_t state[CN_HASH_LEN];
	blake2b(state, CN_HASH_LEN, input, input_size, NULL, 0);

	uint8_t s[CN_HASH_LEN];
	memcpy(s, state, CN_HASH_LEN);

	uint64_t pos = 0;

	for (int round = 0; round < 4; round++) {
		for (int i = 0; i < 4; i++) {
			uint8_t idx = s[pos % 32];
			pos = (idx * 31 + round) & 0x7fff;
			pos = pos % c->mem_size;
			pos &= ~15u;

			uint8_t block[16];
			memcpy(block, c->mem + pos, 16);

			if (c->is_heavy) {
				uint8_t aes_key[16];
				memcpy(aes_key, s, 16);
				__m128i rk[11];
				cn_aes_key_expand(aes_key, rk);
				__m128i data = _mm_load_si128((__m128i *)block);
				for (int k = 0; k < 11; k++) {
					data = (k == 10)
						? _mm_aesenclast_si128(data, rk[k])
						: _mm_aesenc_si128(data, rk[k]);
				}
				memcpy(block, &data, 16);
			}

			for (int b = 0; b < 16; b++) {
				s[(i * 4 + b) % 32] ^= block[b];
			}

			pos = s[pos % 32];
		}
	}

	blake2b(output, CN_OUT_LEN, s, CN_HASH_LEN, NULL, 0);
	return 0;
}

/* --- CN Pico export symbols --- */

frostrig_cryptonight_ctx *frostrig_cn_create_pico(void)
{
	return cn_ctx_create(0);
}

void frostrig_cn_destroy_pico(frostrig_cryptonight_ctx *h)
{
	cn_ctx_destroy(h);
}

int frostrig_cn_prepare_pico(frostrig_cryptonight_ctx *h,
                             const void *key, size_t key_size)
{
	return cn_ctx_prepare(h, key, key_size);
}

int frostrig_cn_hash_pico(frostrig_cryptonight_ctx *h,
                          const void *input, size_t input_size,
                          void *output)
{
	return cn_ctx_hash(h, input, input_size, output);
}

/* --- CN Heavy export symbols --- */

frostrig_cryptonight_ctx *frostrig_cn_create_heavy(void)
{
	return cn_ctx_create(1);
}

void frostrig_cn_destroy_heavy(frostrig_cryptonight_ctx *h)
{
	cn_ctx_destroy(h);
}

int frostrig_cn_prepare_heavy(frostrig_cryptonight_ctx *h,
                              const void *key, size_t key_size)
{
	return cn_ctx_prepare(h, key, key_size);
}

int frostrig_cn_hash_heavy(frostrig_cryptonight_ctx *h,
                           const void *input, size_t input_size,
                           void *output)
{
	return cn_ctx_hash(h, input, input_size, output);
}
