package aes

import "core:mem"

// rx_vec_i128 = 4 x u32, memory order [x,y,z,w] (little-endian)
VecI :: [4]u32

set_int_vec :: proc(i3, i2, i1, i0: u32) -> VecI {
	return VecI{i0, i1, i2, i3}
}

load_vec :: proc(buf: []u8, off: int) -> VecI {
	return VecI{
		cast(u32)buf[off + 0] | cast(u32)buf[off + 1] << 8 | cast(u32)buf[off + 2] << 16 | cast(u32)buf[off + 3] << 24,
		cast(u32)buf[off + 4] | cast(u32)buf[off + 5] << 8 | cast(u32)buf[off + 6] << 16 | cast(u32)buf[off + 7] << 24,
		cast(u32)buf[off + 8] | cast(u32)buf[off + 9] << 8 | cast(u32)buf[off + 10] << 16 | cast(u32)buf[off + 11] << 24,
		cast(u32)buf[off + 12] | cast(u32)buf[off + 13] << 8 | cast(u32)buf[off + 14] << 16 | cast(u32)buf[off + 15] << 24,
	}
}

store_vec :: proc(buf: []u8, off: int, v: VecI) {
	for i in 0 ..< 4 {
		buf[off + i * 4] = cast(u8)(v[i])
		buf[off + i * 4 + 1] = cast(u8)(v[i] >> 8)
		buf[off + i * 4 + 2] = cast(u8)(v[i] >> 16)
		buf[off + i * 4 + 3] = cast(u8)(v[i] >> 24)
	}
}

// soft AES, matches hardware AES-NI results
aesenc :: proc(v, key: VecI) -> VecI {
	s0 := v[3]
	s1 := v[2]
	s2 := v[1]
	s3 := v[0]
	e0 := aes_lut_enc[0]
	e1 := aes_lut_enc[1]
	e2 := aes_lut_enc[2]
	e3 := aes_lut_enc[3]
	out := set_int_vec(
		e0[s0 & 0xff] ~ e1[(s3 >> 8) & 0xff] ~ e2[(s2 >> 16) & 0xff] ~ e3[s1 >> 24],
		e0[s1 & 0xff] ~ e1[(s0 >> 8) & 0xff] ~ e2[(s3 >> 16) & 0xff] ~ e3[s2 >> 24],
		e0[s2 & 0xff] ~ e1[(s1 >> 8) & 0xff] ~ e2[(s0 >> 16) & 0xff] ~ e3[s3 >> 24],
		e0[s3 & 0xff] ~ e1[(s2 >> 8) & 0xff] ~ e2[(s1 >> 16) & 0xff] ~ e3[s0 >> 24],
	)
	return out ~ key
}

aesdec :: proc(v, key: VecI) -> VecI {
	s0 := v[3]
	s1 := v[2]
	s2 := v[1]
	s3 := v[0]
	d0 := aes_lut_dec[0]
	d1 := aes_lut_dec[1]
	d2 := aes_lut_dec[2]
	d3 := aes_lut_dec[3]
	out := set_int_vec(
		d0[s0 & 0xff] ~ d1[(s1 >> 8) & 0xff] ~ d2[(s2 >> 16) & 0xff] ~ d3[s3 >> 24],
		d0[s1 & 0xff] ~ d1[(s2 >> 8) & 0xff] ~ d2[(s3 >> 16) & 0xff] ~ d3[s0 >> 24],
		d0[s2 & 0xff] ~ d1[(s3 >> 8) & 0xff] ~ d2[(s0 >> 16) & 0xff] ~ d3[s1 >> 24],
		d0[s3 & 0xff] ~ d1[(s0 >> 8) & 0xff] ~ d2[(s1 >> 16) & 0xff] ~ d3[s2 >> 24],
	)
	return out ~ key
}

AES_GEN_1R_KEY0 :: u32(0xb4f44917)
AES_GEN_1R_KEY1 :: u32(0xdbb5552b)
AES_GEN_1R_KEY2 :: u32(0x62716609)
AES_GEN_1R_KEY3 :: u32(0x6daca553)
AES_GEN_1R_KEY4 :: u32(0x0da1dc4e)
AES_GEN_1R_KEY5 :: u32(0x1725d378)
AES_GEN_1R_KEY6 :: u32(0x846a710d)
AES_GEN_1R_KEY7 :: u32(0x6d7caf07)
AES_GEN_1R_KEY8 :: u32(0x3e20e345)
AES_GEN_1R_KEY9 :: u32(0xf4c0794f)
AES_GEN_1R_KEY10 :: u32(0x9f947ec6)
AES_GEN_1R_KEY11 :: u32(0x3f1262f1)
AES_GEN_1R_KEY12 :: u32(0x49169154)
AES_GEN_1R_KEY13 :: u32(0x16314c88)
AES_GEN_1R_KEY14 :: u32(0xb1ba317c)
AES_GEN_1R_KEY15 :: u32(0x6aef8135)

AES_GEN_4R_KEY0 :: u32(0x99e5d23f)
AES_GEN_4R_KEY1 :: u32(0x2f546d2b)
AES_GEN_4R_KEY2 :: u32(0xd1833ddb)
AES_GEN_4R_KEY3 :: u32(0x6421aadd)
AES_GEN_4R_KEY4 :: u32(0xa5dfcde5)
AES_GEN_4R_KEY5 :: u32(0x06f79d53)
AES_GEN_4R_KEY6 :: u32(0xb6913f55)
AES_GEN_4R_KEY7 :: u32(0xb20e3450)
AES_GEN_4R_KEY8 :: u32(0x171c02bf)
AES_GEN_4R_KEY9 :: u32(0x0aa4679f)
AES_GEN_4R_KEY10 :: u32(0x515e7baf)
AES_GEN_4R_KEY11 :: u32(0x5c3ed904)
AES_GEN_4R_KEY12 :: u32(0xd8ded291)
AES_GEN_4R_KEY13 :: u32(0xcd673785)
AES_GEN_4R_KEY14 :: u32(0xe78f5d08)
AES_GEN_4R_KEY15 :: u32(0x85623763)
AES_GEN_4R_KEY16 :: u32(0x229effb4)
AES_GEN_4R_KEY17 :: u32(0x3d518b6d)
AES_GEN_4R_KEY18 :: u32(0xe3d6a7a6)
AES_GEN_4R_KEY19 :: u32(0xb5826f73)
AES_GEN_4R_KEY20 :: u32(0xb272b7d2)
AES_GEN_4R_KEY21 :: u32(0xe9024d4e)
AES_GEN_4R_KEY22 :: u32(0x9c10b3d9)
AES_GEN_4R_KEY23 :: u32(0xc7566bf3)
AES_GEN_4R_KEY24 :: u32(0xf63befa7)
AES_GEN_4R_KEY25 :: u32(0x2ba9660a)
AES_GEN_4R_KEY26 :: u32(0xf765a38b)
AES_GEN_4R_KEY27 :: u32(0xf273c9e7)
AES_GEN_4R_KEY28 :: u32(0xc0b0762d)
AES_GEN_4R_KEY29 :: u32(0x0c06d1fd)
AES_GEN_4R_KEY30 :: u32(0x915839de)
AES_GEN_4R_KEY31 :: u32(0x7a7cd609)

AES_HASH_1R_STATE0 :: u32(0xd7983aad)
AES_HASH_1R_STATE1 :: u32(0xcc82db47)
AES_HASH_1R_STATE2 :: u32(0x9fa856de)
AES_HASH_1R_STATE3 :: u32(0x92b52c0d)
AES_HASH_1R_STATE4 :: u32(0xace78057)
AES_HASH_1R_STATE5 :: u32(0xf59e125a)
AES_HASH_1R_STATE6 :: u32(0x15c7b798)
AES_HASH_1R_STATE7 :: u32(0x338d996e)
AES_HASH_1R_STATE8 :: u32(0xe8a07ce4)
AES_HASH_1R_STATE9 :: u32(0x5079506b)
AES_HASH_1R_STATE10 :: u32(0xae62c7d0)
AES_HASH_1R_STATE11 :: u32(0x6a770017)
AES_HASH_1R_STATE12 :: u32(0x7e994948)
AES_HASH_1R_STATE13 :: u32(0x79a10005)
AES_HASH_1R_STATE14 :: u32(0x07ad828d)
AES_HASH_1R_STATE15 :: u32(0x630a240c)

AES_HASH_1R_XKEY0 :: u32(0x06890201)
AES_HASH_1R_XKEY1 :: u32(0x90dc56bf)
AES_HASH_1R_XKEY2 :: u32(0x8b24949f)
AES_HASH_1R_XKEY3 :: u32(0xf6fa8389)
AES_HASH_1R_XKEY4 :: u32(0xed18f99b)
AES_HASH_1R_XKEY5 :: u32(0xee1043c6)
AES_HASH_1R_XKEY6 :: u32(0x51f4e03c)
AES_HASH_1R_XKEY7 :: u32(0x61b263d1)

// fillAes1Rx4: fill 'buffer' (outsize multiple of 64) from 512-bit 'state'
fillAes1Rx4 :: proc(state: []u8, outsize: int, buffer: []u8) {
	key0 := set_int_vec(AES_GEN_1R_KEY0, AES_GEN_1R_KEY1, AES_GEN_1R_KEY2, AES_GEN_1R_KEY3)
	key1 := set_int_vec(AES_GEN_1R_KEY4, AES_GEN_1R_KEY5, AES_GEN_1R_KEY6, AES_GEN_1R_KEY7)
	key2 := set_int_vec(AES_GEN_1R_KEY8, AES_GEN_1R_KEY9, AES_GEN_1R_KEY10, AES_GEN_1R_KEY11)
	key3 := set_int_vec(AES_GEN_1R_KEY12, AES_GEN_1R_KEY13, AES_GEN_1R_KEY14, AES_GEN_1R_KEY15)
	s0 := load_vec(state, 0)
	s1 := load_vec(state, 16)
	s2 := load_vec(state, 32)
	s3 := load_vec(state, 48)
	off := 0
	for off < outsize {
		s0 = aesdec(s0, key0)
		s1 = aesenc(s1, key1)
		s2 = aesdec(s2, key2)
		s3 = aesenc(s3, key3)
		store_vec(buffer, off + 0, s0)
		store_vec(buffer, off + 16, s1)
		store_vec(buffer, off + 32, s2)
		store_vec(buffer, off + 48, s3)
		off += 64
	}
	store_vec(state, 0, s0)
	store_vec(state, 16, s1)
	store_vec(state, 32, s2)
	store_vec(state, 48, s3)
}

// fillAes4Rx4: 4 AES rounds per 64 bytes
fillAes4Rx4 :: proc(state: []u8, outsize: int, buffer: []u8) {
	k0 := set_int_vec(AES_GEN_4R_KEY0, AES_GEN_4R_KEY1, AES_GEN_4R_KEY2, AES_GEN_4R_KEY3)
	k1 := set_int_vec(AES_GEN_4R_KEY4, AES_GEN_4R_KEY5, AES_GEN_4R_KEY6, AES_GEN_4R_KEY7)
	k2 := set_int_vec(AES_GEN_4R_KEY8, AES_GEN_4R_KEY9, AES_GEN_4R_KEY10, AES_GEN_4R_KEY11)
	k3 := set_int_vec(AES_GEN_4R_KEY12, AES_GEN_4R_KEY13, AES_GEN_4R_KEY14, AES_GEN_4R_KEY15)
	k4 := set_int_vec(AES_GEN_4R_KEY16, AES_GEN_4R_KEY17, AES_GEN_4R_KEY18, AES_GEN_4R_KEY19)
	k5 := set_int_vec(AES_GEN_4R_KEY20, AES_GEN_4R_KEY21, AES_GEN_4R_KEY22, AES_GEN_4R_KEY23)
	k6 := set_int_vec(AES_GEN_4R_KEY24, AES_GEN_4R_KEY25, AES_GEN_4R_KEY26, AES_GEN_4R_KEY27)
	k7 := set_int_vec(AES_GEN_4R_KEY28, AES_GEN_4R_KEY29, AES_GEN_4R_KEY30, AES_GEN_4R_KEY31)
	s0 := load_vec(state, 0)
	s1 := load_vec(state, 16)
	s2 := load_vec(state, 32)
	s3 := load_vec(state, 48)
	off := 0
	for off < outsize {
		s0 = aesdec(s0, k0)
		s1 = aesenc(s1, k0)
		s2 = aesdec(s2, k4)
		s3 = aesenc(s3, k4)
		s0 = aesdec(s0, k1)
		s1 = aesenc(s1, k1)
		s2 = aesdec(s2, k5)
		s3 = aesenc(s3, k5)
		s0 = aesdec(s0, k2)
		s1 = aesenc(s1, k2)
		s2 = aesdec(s2, k6)
		s3 = aesenc(s3, k6)
		s0 = aesdec(s0, k3)
		s1 = aesenc(s1, k3)
		s2 = aesdec(s2, k7)
		s3 = aesenc(s3, k7)
		store_vec(buffer, off + 0, s0)
		store_vec(buffer, off + 16, s1)
		store_vec(buffer, off + 32, s2)
		store_vec(buffer, off + 48, s3)
		off += 64
	}
}

// hashAes1Rx4: 512-bit hash of 'input' (multiple of 64) via 4 AES lanes
hashAes1Rx4 :: proc(input: []u8, inputSize: int, hash: []u8) {
	st0 := set_int_vec(AES_HASH_1R_STATE0, AES_HASH_1R_STATE1, AES_HASH_1R_STATE2, AES_HASH_1R_STATE3)
	st1 := set_int_vec(AES_HASH_1R_STATE4, AES_HASH_1R_STATE5, AES_HASH_1R_STATE6, AES_HASH_1R_STATE7)
	st2 := set_int_vec(AES_HASH_1R_STATE8, AES_HASH_1R_STATE9, AES_HASH_1R_STATE10, AES_HASH_1R_STATE11)
	st3 := set_int_vec(AES_HASH_1R_STATE12, AES_HASH_1R_STATE13, AES_HASH_1R_STATE14, AES_HASH_1R_STATE15)
	off := 0
	for off < inputSize {
		in0 := load_vec(input, off + 0)
		in1 := load_vec(input, off + 16)
		in2 := load_vec(input, off + 32)
		in3 := load_vec(input, off + 48)
		st0 = aesenc(st0, in0)
		st1 = aesdec(st1, in1)
		st2 = aesenc(st2, in2)
		st3 = aesdec(st3, in3)
		off += 64
	}
	xk0 := set_int_vec(AES_HASH_1R_XKEY0, AES_HASH_1R_XKEY1, AES_HASH_1R_XKEY2, AES_HASH_1R_XKEY3)
	xk1 := set_int_vec(AES_HASH_1R_XKEY4, AES_HASH_1R_XKEY5, AES_HASH_1R_XKEY6, AES_HASH_1R_XKEY7)
	st0 = aesenc(st0, xk0)
	st1 = aesdec(st1, xk0)
	st2 = aesenc(st2, xk0)
	st3 = aesdec(st3, xk0)
	st0 = aesenc(st0, xk1)
	st1 = aesdec(st1, xk1)
	st2 = aesenc(st2, xk1)
	st3 = aesdec(st3, xk1)
	store_vec(hash, 0, st0)
	store_vec(hash, 16, st1)
	store_vec(hash, 32, st2)
	store_vec(hash, 48, st3)
}
