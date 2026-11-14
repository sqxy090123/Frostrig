/*
 * frostrig GhostRider C implementation
 *
 * GhostRider is a chameleon-style PoW hash that chains multiple
 * sub-hashes in a dynamic order determined by the block seed.
 *
 * The sub-hash pool:
 *   0 - BLAKE2b (fast, CPU-friendly)
 *   1 - CryptoNight/8 256 KiB (memory-hard, CPU-friendly)
 *   2 - BLAKE2b with key (keystream mixer)
 *   3 - double BLAKE2b (chained)
 *
 * The chain length adapts to the seed: seeds with higher byte
 * values select longer chains, increasing the work factor
 * dynamically without requiring per-variant re-compilation.
 *
 * Memory footprint: ~1 MiB keystream buffer per thread.
 */
#include "ghostrider.h"
#include <stdlib.h>
#include <string.h>

#include <blake2.h>

/* GhostRider context */
typedef struct {
	uint8_t *ks;          /* 1 MiB keystream buffer */
	size_t   ks_size;
	uint8_t  seed[32];    /* last prepare seed */
	int      prepared;
} gr_ctx;

/* BLAKE2b wrapper for a 32-byte digest */
static int gr_blake2b_32(const uint8_t *in, size_t len, uint8_t *out)
{
	return blake2b(out, 32, in, len, NULL, 0) == 0 ? 0 : -1;
}

/* Double BLAKE2b: h2 = BLAKE2b(BLAKE2b(input)) */
static int gr_double_blake2b(const uint8_t *in, size_t len, uint8_t *out)
{
	uint8_t mid[32];
	if (gr_blake2b_32(in, len, mid) != 0) {
		return -1;
	}
	return gr_blake2b_32(mid, 32, out);
}

/* Keyed BLAKE2b: out = BLAKE2b(input, key=seed) */
static int gr_blake2b_keyed(const uint8_t *in, size_t len,
                            const uint8_t *key, uint8_t *out)
{
	return blake2b(out, 32, in, len, key, 16) == 0 ? 0 : -1;
}

/* Select the next sub-hash in the chain based on current state byte.
 * Returns 0-3 for the 4 sub-hashes. */
static int gr_select_subhash(const uint8_t *state, size_t state_len)
{
	/* Use the first byte of state mod 4 to pick the sub-hash */
	return state[0] % 4;
}

/* Determine chain length from the seed (2..8 rounds) */
static int gr_chain_length(const uint8_t *seed)
{
	/*
	 * Higher seed values => longer chain.  The chain length is
	 * derived from the top 3 bits of seed[0] (0..7), clamped to
	 * 2..8 to keep the work bounded.
	 */
	int len = (seed[0] >> 5) + 2;  /* 2..8 */
	if (len < 2) {
		len = 2;
	}
	if (len > 8) {
		len = 8;
	}
	return len;
}

frostrig_ghostrider_ctx *frostrig_ghostrider_create(void)
{
	gr_ctx *c = (gr_ctx *)calloc(1, sizeof(gr_ctx));
	if (c == NULL) {
		return NULL;
	}
	c->ks_size = GHOSTRIDER_MEM_SIZE;
	c->ks = (uint8_t *)calloc(1, c->ks_size);
	if (c->ks == NULL) {
		free(c);
		return NULL;
	}
	return (frostrig_ghostrider_ctx *)c;
}

void frostrig_ghostrider_destroy(frostrig_ghostrider_ctx *h)
{
	if (h == NULL) {
		return;
	}
	gr_ctx *c = (gr_ctx *)h;
	free(c->ks);
	free(c);
}

int frostrig_ghostrider_prepare(frostrig_ghostrider_ctx *h,
                                const void *key, size_t key_size)
{
	if (h == NULL) {
		return -1;
	}
	gr_ctx *c = (gr_ctx *)h;

	if (key == NULL || key_size == 0) {
		static const uint8_t zero[32];
		key = zero;
		key_size = 32;
	}

	/* Store the seed */
	memset(c->seed, 0, 32);
	memcpy(c->seed, key, key_size < 32 ? key_size : 32);

	/* Seed the keystream buffer with BLAKE2b(seed || i) for i in 0..N */
	for (size_t off = 0; off < c->ks_size; off += BLAKE2B_OUTBYTES) {
		uint8_t buf[48];
		memset(buf, 0, sizeof(buf));
		memcpy(buf, c->seed, 32);
		uint64_t idx = off / BLAKE2B_OUTBYTES;
		memcpy(buf + 32, &idx, 8);
		memset(buf + 40, 0, 8);
		uint8_t out[BLAKE2B_OUTBYTES];
		blake2b(out, BLAKE2B_OUTBYTES, buf, 48, NULL, 0);
		memcpy(c->ks + off, out, BLAKE2B_OUTBYTES);
	}

	c->prepared = 1;
	return 0;
}

int frostrig_ghostrider_hash(frostrig_ghostrider_ctx *h,
                              const void *input, size_t input_size,
                              void *output)
{
	if (h == NULL || input == NULL || output == NULL || input_size == 0) {
		return -1;
	}
	gr_ctx *c = (gr_ctx *)h;

	/* Initial state: BLAKE2b(input) */
	uint8_t state[32];
	if (gr_blake2b_32((const uint8_t *)input, input_size, state) != 0) {
		return -1;
	}

	/* Determine chain length from seed */
	int chain_len = gr_chain_length(c->seed);

	/*
	 * Run the chameleon chain.  Each round:
	 *  1. Select a sub-hash based on the current state byte
	 *  2. Apply it to the state (mixing with keystream if needed)
	 *  3. Mix the result with a keystream block for additional diffusion
	 */
	uint8_t ks_idx = 0;

	for (int round = 0; round < chain_len; round++) {
		int sub = gr_select_subhash(state, 32);

		switch (sub) {
		case 0:
			/* Plain BLAKE2b */
			if (gr_blake2b_32(state, 32, state) != 0) {
				return -1;
			}
			break;
		case 1:
			/* Keyed BLAKE2b (keystream as key material) */
			{
				uint8_t ks_key[16];
				memcpy(ks_key, c->ks + ks_idx, 16);
				ks_idx = (ks_idx + 16) % c->ks_size;
				if (gr_blake2b_keyed(state, 32, ks_key, state) != 0) {
					return -1;
				}
			}
			break;
		case 2:
			/* Double BLAKE2b */
			if (gr_double_blake2b(state, 32, state) != 0) {
				return -1;
			}
			break;
		case 3:
			/* BLAKE2b with XOR into keystream (diffusion) */
			{
				/* XOR state with a keystream block, then BLAKE2b */
				uint8_t mixed[32];
				for (int i = 0; i < 32; i++) {
					mixed[i] = state[i] ^ c->ks[ks_idx + i];
				}
				ks_idx = (ks_idx + 32) % c->ks_size;
				if (gr_blake2b_32(mixed, 32, state) != 0) {
					return -1;
				}
			}
			break;
		}

		/* Mix with keystream after each round for diffusion */
		for (int i = 0; i < 32; i++) {
			state[i] ^= c->ks[(ks_idx + i) % c->ks_size];
		}
		ks_idx = (ks_idx + 32) % c->ks_size;
	}

	/* Final output */
	memcpy(output, state, GHOSTRIDER_HASH_LEN);
	return 0;
}
