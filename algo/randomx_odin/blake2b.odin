package frostrig_randomx_odin

import "core:mem"

BLAKE2B_BLOCKBYTES :: 128
BLAKE2B_OUTBYTES :: 64
BLAKE2B_KEYBYTES :: 64

Blake2b_State :: struct {
	h:       [8]u64,
	t:       [2]u64,
	f:       [2]u64,
	buf:     [BLAKE2B_BLOCKBYTES]u8,
	buflen:  u32,
	outlen:  u32,
	last_node: u8,
}

blake2b_IV: [8]u64 = {
	0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
	0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
	0x510e527fade682d1, 0x9b05688c2b3e6c1f,
	0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
}

blake2b_sigma: [12][16]int = {
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
	{14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
	{11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
	{7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
	{9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
	{2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
	{12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
	{13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
	{6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
	{10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
	{14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
}

load64_le :: proc(p: []u8) -> u64 {
	return u64(p[0]) | u64(p[1]) << 8 | u64(p[2]) << 16 | u64(p[3]) << 24 |
	       u64(p[4]) << 32 | u64(p[5]) << 40 | u64(p[6]) << 48 | u64(p[7]) << 56
}

store64_le :: proc(p: []u8, w: u64) {
	p[0] = u8(w)
	p[1] = u8(w >> 8)
	p[2] = u8(w >> 16)
	p[3] = u8(w >> 24)
	p[4] = u8(w >> 32)
	p[5] = u8(w >> 40)
	p[6] = u8(w >> 48)
	p[7] = u8(w >> 56)
}

load32_le :: proc(p: []u8) -> u32 {
	return u32(p[0]) | u32(p[1]) << 8 | u32(p[2]) << 16 | u32(p[3]) << 24
}

store32_le :: proc(p: []u8, w: u32) {
	p[0] = u8(w)
	p[1] = u8(w >> 8)
	p[2] = u8(w >> 16)
	p[3] = u8(w >> 24)
}

rotr64 :: #force_inline proc(w: u64, c: u32) -> u64 {
	return (w >> c) | (w << (64 - c))
}

blake2b_set_lastnode :: proc(S: ^Blake2b_State) {
	S.f[1] = 0xFFFFFFFFFFFFFFFF
}

blake2b_set_lastblock :: proc(S: ^Blake2b_State) {
	if S.last_node != 0 {
		blake2b_set_lastnode(S)
	}
	S.f[0] = 0xFFFFFFFFFFFFFFFF
}

blake2b_increment_counter :: proc(S: ^Blake2b_State, inc: u64) {
	S.t[0] += inc
	S.t[1] += (S.t[0] < inc) ? 1 : 0
}

blake2b_init0 :: proc(S: ^Blake2b_State) {
	mem.zero_slice(S.h[:])
	S.t = {0, 0}
	S.f = {0, 0}
	S.buf = {}
	S.buflen = 0
	S.outlen = 0
	S.last_node = 0
	S.h = blake2b_IV
}

blake2b_init_param :: proc(S: ^Blake2b_State, P: []u8) -> int {
	blake2b_init0(S)
	for i in 0 ..< 8 {
		S.h[i] ~= load64_le(P[i*8:])
	}
	S.outlen = u32(P[0])
	return 0
}

blake2b_init :: proc(S: ^Blake2b_State, outlen: u64) -> int {
	// Param block: digest_length(1) key_length(1) fanout(1) depth(1)
	// leaf_length(4) node_offset(8) node_depth(1) inner_length(1)
	// reserved(14) salt(16) personal(16) = 64 bytes
	P: [64]u8
	P[0] = u8(outlen) // digest_length
	P[1] = 0          // key_length
	P[2] = 1          // fanout
	P[3] = 1          // depth
	return blake2b_init_param(S, P[:])
}

blake2b_compress :: proc(S: ^Blake2b_State, block: []u8) {
	m: [16]u64
	v: [16]u64
	for i in 0 ..< 16 {
		m[i] = load64_le(block[i*8:])
	}
	for i in 0 ..< 8 {
		v[i] = S.h[i]
	}
	v[8] = blake2b_IV[0]
	v[9] = blake2b_IV[1]
	v[10] = blake2b_IV[2]
	v[11] = blake2b_IV[3]
	v[12] = blake2b_IV[4] ~ S.t[0]
	v[13] = blake2b_IV[5] ~ S.t[1]
	v[14] = blake2b_IV[6] ~ S.f[0]
	v[15] = blake2b_IV[7] ~ S.f[1]

	for r in 0 ..< 12 {
		// 8 G operations per round
		G(&v, &m, r, 0, 0, 4, 8, 12)
		G(&v, &m, r, 1, 1, 5, 9, 13)
		G(&v, &m, r, 2, 2, 6, 10, 14)
		G(&v, &m, r, 3, 3, 7, 11, 15)
		G(&v, &m, r, 4, 0, 5, 10, 15)
		G(&v, &m, r, 5, 1, 6, 11, 12)
		G(&v, &m, r, 6, 2, 7, 8, 13)
		G(&v, &m, r, 7, 3, 4, 9, 14)
	}
	for i in 0 ..< 8 {
		S.h[i] = S.h[i] ~ v[i] ~ v[i + 8]
	}
}

G :: #force_inline proc(v: ^[16]u64, m: ^[16]u64, r: int, i: int, a: int, b: int, c: int, d: int) {
	v[a] = v[a] + v[b] + m[blake2b_sigma[r][2 * i + 0]]
	v[d] = rotr64(v[d] ~ v[a], 32)
	v[c] = v[c] + v[d]
	v[b] = rotr64(v[b] ~ v[c], 24)
	v[a] = v[a] + v[b] + m[blake2b_sigma[r][2 * i + 1]]
	v[d] = rotr64(v[d] ~ v[a], 16)
	v[c] = v[c] + v[d]
	v[b] = rotr64(v[b] ~ v[c], 63)
}

blake2b_update :: proc(S: ^Blake2b_State, input: []u8) -> int {
	if len(input) == 0 {
		return 0
	}
	if S.f[0] != 0 {
		return -1
	}
	pin := input
	inlen := len(input)
	if S.buflen + u32(inlen) > BLAKE2B_BLOCKBYTES {
		left := S.buflen
		fill := BLAKE2B_BLOCKBYTES - int(left)
		mem.copy(&S.buf[left], raw_data(pin), fill)
		blake2b_increment_counter(S, BLAKE2B_BLOCKBYTES)
		blake2b_compress(S, S.buf[:])
		S.buflen = 0
		inlen -= fill
		pin = pin[fill:]
		for inlen > BLAKE2B_BLOCKBYTES {
			blake2b_increment_counter(S, BLAKE2B_BLOCKBYTES)
			blake2b_compress(S, pin)
			inlen -= BLAKE2B_BLOCKBYTES
			pin = pin[BLAKE2B_BLOCKBYTES:]
		}
	}
	mem.copy(&S.buf[S.buflen], raw_data(pin), inlen)
	S.buflen += u32(inlen)
	return 0
}

blake2b_final :: proc(S: ^Blake2b_State, out: []u8, outlen: u64) -> int {
	buffer: [BLAKE2B_OUTBYTES]u8
	if outlen < u64(S.outlen) {
		return -1
	}
	if S.f[0] != 0 {
		return -1
	}
	blake2b_increment_counter(S, u64(S.buflen))
	blake2b_set_lastblock(S)
	mem.zero_slice(S.buf[S.buflen:BLAKE2B_BLOCKBYTES])
	blake2b_compress(S, S.buf[:])
	for i in 0 ..< 8 {
		store64_le(buffer[i*8:], S.h[i])
	}
	mem.copy(raw_data(out), &buffer[0], int(S.outlen))
	return 0
}

blake2b :: proc(out: []u8, outlen: u64, input: []u8, key: []u8) -> int {
	S: Blake2b_State
	if len(input) == 0 && input != nil {
		// NULL in with inlen>0 is invalid; empty ok
	}
	if outlen == 0 || outlen > BLAKE2B_OUTBYTES {
		return -1
	}
	if len(key) > BLAKE2B_KEYBYTES {
		return -1
	}
	if len(key) > 0 {
		// keyed init: P.key_length = keylen; update full block with key
		P: [64]u8
		P[0] = u8(outlen)
		P[1] = u8(len(key))
		P[2] = 1
		P[3] = 1
		if blake2b_init_param(&S, P[:]) < 0 {
			return -1
		}
		block: [BLAKE2B_BLOCKBYTES]u8
		mem.copy(&block[0], raw_data(key), len(key))
		if blake2b_update(&S, block[:]) < 0 {
			return -1
		}
	} else {
		if blake2b_init(&S, outlen) < 0 {
			return -1
		}
	}
	if blake2b_update(&S, input) < 0 {
		return -1
	}
	return blake2b_final(&S, out, outlen)
}

blake2b_long :: proc(pout: []u8, outlen: u64, input: []u8) -> int {
	out := pout
	outlen_bytes: [4]u8
	if outlen > 0xFFFFFFFF {
		return -1
	}
	store32_le(outlen_bytes[:], u32(outlen))
	if outlen <= BLAKE2B_OUTBYTES {
		S: Blake2b_State
		if blake2b_init(&S, outlen) < 0 {
			return -1
		}
		if blake2b_update(&S, outlen_bytes[:]) < 0 {
			return -1
		}
		if blake2b_update(&S, input) < 0 {
			return -1
		}
		if blake2b_final(&S, out, outlen) < 0 {
			return -1
		}
		return 0
	} else {
		out_buffer: [BLAKE2B_OUTBYTES]u8
		in_buffer: [BLAKE2B_OUTBYTES]u8
		S: Blake2b_State
		if blake2b_init(&S, BLAKE2B_OUTBYTES) < 0 {
			return -1
		}
		if blake2b_update(&S, outlen_bytes[:]) < 0 {
			return -1
		}
		if blake2b_update(&S, input) < 0 {
			return -1
		}
		if blake2b_final(&S, out_buffer[:], BLAKE2B_OUTBYTES) < 0 {
			return -1
		}
		mem.copy(raw_data(out), &out_buffer[0], BLAKE2B_OUTBYTES / 2)
		out = out[BLAKE2B_OUTBYTES / 2:]
		toproduce := u32(outlen - BLAKE2B_OUTBYTES / 2)
		for toproduce > BLAKE2B_OUTBYTES {
			mem.copy(&in_buffer[0], &out_buffer[0], BLAKE2B_OUTBYTES)
			if blake2b(out_buffer[:], BLAKE2B_OUTBYTES, in_buffer[:], nil) < 0 {
				return -1
			}
			mem.copy(raw_data(out), &out_buffer[0], BLAKE2B_OUTBYTES / 2)
			out = out[BLAKE2B_OUTBYTES / 2:]
			toproduce -= BLAKE2B_OUTBYTES / 2
		}
		mem.copy(&in_buffer[0], &out_buffer[0], BLAKE2B_OUTBYTES)
		if blake2b(out_buffer[:], u64(toproduce), in_buffer[:], nil) < 0 {
			return -1
		}
		mem.copy(raw_data(out), &out_buffer[0], cast(int)(toproduce))
		return 0
	}
}


