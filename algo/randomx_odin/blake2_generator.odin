package frostrig_randomx_odin

import "core:mem"

// Blake2Generator — port of randomx/src/blake2_generator.cpp
Blake2Generator :: struct {
	data:       [64]u8,
	data_index: int,
}

MAX_SEED_SIZE :: 60

blake2_gen_init :: proc(seed: []u8, nonce: u32 = 0) -> Blake2Generator {
	g: Blake2Generator
	g.data = {}
	n := min(len(seed), MAX_SEED_SIZE)
	copy(g.data[:], seed[:n])
	store32_le(g.data[MAX_SEED_SIZE:], nonce)
	g.data_index = 64
	return g
}

check_data :: proc(g: ^Blake2Generator, bytes_needed: int) {
	if g.data_index + bytes_needed > 64 {
		blake2b(g.data[:], 64, g.data[:], {})
		g.data_index = 0
	}
}

get_byte :: proc(g: ^Blake2Generator) -> u8 {
	check_data(g, 1)
	v := g.data[g.data_index]
	g.data_index += 1
	return v
}

get_u32 :: proc(g: ^Blake2Generator) -> u32 {
	check_data(g, 4)
	v := load32_le(g.data[g.data_index:])
	g.data_index += 4
	return v
}
