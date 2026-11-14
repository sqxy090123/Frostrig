/*
 * frostrig CryptoNight C implementation
 *
 * Two variants:
 *   CN_PICO  - 256 KiB memory pool, classic CryptoNight/8 (no AES)
 *   CN_HEAVY - 4 MiB memory pool, CryptoNight/8 with AES-128-ECB
 *
 * The memory pool is seeded in prepare() via BLAKE2b(key || counter).
 * hash() runs one full CryptoNight/8 pass over the memory pool.
 *
 * The AES-128-ECB step (heavy variant only) is implemented two ways:
 *   - A portable software AES-128 (always available, deterministic).
 *   - An optional AES-NI intrinsic fast path, enabled by defining
 *     FROSTRIG_CN_AESNI at compile time (e.g. gcc -maes).  When not
 *     defined, the software path is used, so the translation unit
 *     compiles on ANY compiler/target with no arch flags required.
 *
 * Build (Linux, portable, no arch flags):
 *   cc -O2 -fPIC -I third_party/argon2/include \
 *      -I third_party/argon2/src -I algo/cryptonight \
 *      algo/cryptonight/cryptonight.c -c -o algo/cryptonight/cryptonight.o
 *
 * Build (Linux, AES-NI fast path):
 *   cc -O3 -march=native -DFROSTRIG_CN_AESNI ... (requires AES-NI CPU)
 */
#include "cryptonight.h"
#include <stdlib.h>
#include <string.h>

#include "blake2.h"

/* Optional AES-NI fast path. */
#ifdef FROSTRIG_CN_AESNI
#include <wmmintrin.h>
#endif

#define CN_HASH_LEN 32
#define CN_OUT_LEN  32

/* Per-variant memory pool sizes (bytes) */
#define CN_PICO_MEM  (256 * 1024)
#define CN_HEAVY_MEM (4 * 1024 * 1024)

/* ------------------------------------------------------------------
 * Portable AES-128 (encrypt only, single block).  Used as the default
 * implementation for the CN-heavy AES step so the build has no hard
 * dependency on AES-NI intrinsics or compiler arch flags.
 * ---------------------------------------------------------------- */

static const uint8_t sbox[256] = {
	0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
	0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
	0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
	0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
	0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
	0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
	0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
	0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
	0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
	0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
	0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
	0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
	0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
	0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
	0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
	0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

static const uint8_t rcon[10] = {
	0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

static uint8_t xtime(uint8_t x)
{
	/* Multiply by 2 (0x02) in GF(2^8) with the 0x11b reduction polynomial. */
	return (uint8_t)(((x & 0x7f) << 1) ^ ((x & 0x80) ? 0x1b : 0));
}

/* xtime(x) * 3 */
static uint8_t xtime3(uint8_t x)
{
	return (uint8_t)(xtime(x) ^ x);
}

/* Key expansion: 16-byte key -> 44 words (176 bytes).  W[i] for i in 0..43. */
static void cn_aes_key_expand(const uint8_t key[16], uint8_t rk[176])
{
	memcpy(rk, key, 16);
	for (int i = 4; i < 44; i++) {
		uint8_t t[4];
		/* copy word i-1 */
		t[0] = rk[(i - 1) * 4 + 0];
		t[1] = rk[(i - 1) * 4 + 1];
		t[2] = rk[(i - 1) * 4 + 2];
		t[3] = rk[(i - 1) * 4 + 3];
		if (i % 4 == 0) {
			/* RotWord + SubWord + Rcon */
			uint8_t tmp = t[0];
			t[0] = t[1];
			t[1] = t[2];
			t[2] = t[3];
			t[3] = tmp;
			for (int j = 0; j < 4; j++) {
				t[j] = sbox[t[j]];
			}
			t[0] ^= rcon[i / 4 - 1];
		}
		for (int j = 0; j < 4; j++) {
			rk[i * 4 + j] = rk[(i - 4) * 4 + j] ^ t[j];
		}
	}
}

/* Encrypt one 16-byte block with AES-128 using the 176-byte expanded key.
 * State is kept row-major (s[i*4 + j] = row i, col j) matching the
 * verified reference (tiny-AES-c).  Round key byte layout:
 * rk[round*16 + 4*col + row] (col-major key storage from key expansion). */
static void cn_aes_encrypt_block(const uint8_t in[16], const uint8_t rk[176],
                                  uint8_t out[16])
{
	uint8_t s[16];
	/* state[row][col] = in[col*4 + row]  ->  s[4*row + col] = in[4*col + row] */
	for (int r = 0; r < 4; r++) {
		for (int c = 0; c < 4; c++) {
			s[4 * r + c] = in[4 * c + r];
		}
	}

	/* AddRoundKey: state[r][c] (at s[4r+c]) XORs round-key word (R*4+c) byte r
	 * = rk[R*16 + 4c + r].  Round-0 key is the raw key (s[4r+c] ^= rk[4c+r]). */
	for (int i = 0; i < 16; i++) {
		int r = i / 4, c = i % 4;
		s[i] ^= rk[4 * c + r];
	}

	uint8_t n[16];
	for (int round = 1; round <= 10; round++) {
		/* SubBytes */
		for (int i = 0; i < 16; i++) {
			s[i] = sbox[s[i]];
		}
		/* ShiftRows: shift row r left by r columns */
		for (int r = 0; r < 4; r++) {
			for (int c = 0; c < 4; c++) {
				n[4 * r + c] = s[4 * r + ((c + r) % 4)];
			}
		}
		memcpy(s, n, 16);
		/* MixColumns (skip in the final round).  Column c holds bytes
		 * s[c], s[4+c], s[8+c], s[12+c] in the row-major state. */
		if (round < 10) {
			for (int c = 0; c < 4; c++) {
				uint8_t a0 = s[c], a1 = s[4 + c], a2 = s[8 + c], a3 = s[12 + c];
				n[c]       = (uint8_t)(xtime(a0) ^ xtime3(a1) ^ a2 ^ a3);
				n[4 + c]   = (uint8_t)(a0 ^ xtime(a1) ^ xtime3(a2) ^ a3);
				n[8 + c]   = (uint8_t)(a0 ^ a1 ^ xtime(a2) ^ xtime3(a3));
				n[12 + c]  = (uint8_t)(xtime3(a0) ^ a1 ^ a2 ^ xtime(a3));
			}
			memcpy(s, n, 16);
		}
		/* AddRoundKey: state[r][c] (at s[4r+c]) ^= rk[R*16 + 4c + r] */
		for (int i = 0; i < 16; i++) {
			int r = i / 4, c = i % 4;
			s[i] ^= rk[round * 16 + 4 * c + r];
		}
	}

	/* Back to output layout: out[col*4 + row] = s[row*4 + col] */
	for (int r = 0; r < 4; r++) {
		for (int c = 0; c < 4; c++) {
			out[4 * c + r] = s[4 * r + c];
		}
	}
}

#ifdef FROSTRIG_CN_AESNI
/* AES-NI key expansion.  _mm_aesenc is the encryption round (SubBytes+ShiftRows+
 * MixColumns+XorKey) and is the wrong primitive for the key schedule, so we reuse
 * the software key schedule (byte-correct) and expose it as __m128i round keys.
 * _mm_aesenc/_mm_aesenclast consume round keys as raw 16-byte blocks in the
 * standard layout, so the software-expanded bytes drop straight in. */
static void cn_aes_key_expand_ni(const uint8_t key[16], __m128i rk[11])
{
	uint8_t flat[176];
	cn_aes_key_expand(key, flat);
	for (int i = 0; i < 11; i++) {
		rk[i] = _mm_loadu_si128((const __m128i *)(flat + i * 16));
	}
}

static void cn_aes_encrypt_block_ni(const uint8_t in[16], __m128i rk[11],
                                    uint8_t out[16])
{
	/* AES-128 = 10 rounds: initial AddRoundKey(rk[0]) via XOR, then 9 rounds of
	 * SubBytes+ShiftRows+MixColumns+AddRoundKey (_mm_aesenc with rk[1..9]),
	 * then final round without MixColumns (_mm_aesenclast with rk[10]). */
	__m128i d = _mm_xor_si128(_mm_load_si128((__m128i *)in), rk[0]);
	for (int k = 1; k <= 9; k++) {
		d = _mm_aesenc_si128(d, rk[k]);
	}
	d = _mm_aesenclast_si128(d, rk[10]);
	_mm_store_si128((__m128i *)out, d);
}
#endif

typedef struct {
	uint8_t  *mem;
	size_t    mem_size;
	int       is_heavy;
	uint8_t   seed[32];
	int       prepared;
} cn_ctx;

/* Encrypt one 16-byte block (AES-NI fast path when available, else soft). */
static void cn_aes_ecb(const uint8_t key[16], const uint8_t in[16],
                       uint8_t out[16])
{
#ifdef FROSTRIG_CN_AESNI
	__m128i rk[11];
	cn_aes_key_expand_ni(key, rk);
	cn_aes_encrypt_block_ni(in, rk, out);
#else
	uint8_t rk[176];
	cn_aes_key_expand(key, rk);
	cn_aes_encrypt_block(in, rk, out);
#endif
}

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
				uint8_t enc[16];
				cn_aes_ecb(aes_key, block, enc);
				memcpy(block, enc, 16);
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
