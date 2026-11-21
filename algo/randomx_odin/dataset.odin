package frostrig_randomx_odin


// Dataset init — port of randomx/src/dataset.cpp (interpreter path)

CacheSize :: 268435456 // RANDOMX_ARGON_MEMORY * ArgonBlockSize = 262144 * 1024
CacheLineSize :: 64
RANDOMX_CACHE_ACCESSES :: 8

SUPERSCALAR_MUL0 :: u64(6364136223846793005)
SUPERSCALAR_ADD1 :: u64(9298411001130361340)
SUPERSCALAR_ADD2 :: u64(12065312585734608966)
SUPERSCALAR_ADD3 :: u64(9306329213124626780)
SUPERSCALAR_ADD4 :: u64(5281919268842080866)
SUPERSCALAR_ADD5 :: u64(10536153434571861004)
SUPERSCALAR_ADD6 :: u64(3398623926847679864)
SUPERSCALAR_ADD7 :: u64(9549104520008361294)

RANDOMX_ARGON_SALT :: "RandomX\x03"

Dataset_Cache :: struct {
	programs:   [RANDOMX_CACHE_ACCESSES]SuperscalarProgram,
	reciprocal: [dynamic]u64,
	memory:     []u8,
}

get_mix_block :: proc(register_value: u64, memory: []u8) -> []u8 {
	mask := u64(CacheSize / CacheLineSize - 1)
	offset := (register_value & mask) * CacheLineSize
	return memory[offset:offset + CacheLineSize]
}

init_cache :: proc(key: []u8) -> Dataset_Cache {
	cache: Dataset_Cache
	cache.memory = make([]u8, CacheSize)

	instance: Argon2_Instance
	blocks_ptr := transmute([^]Block)(raw_data(cache.memory))
	instance.memory = blocks_ptr[:CacheSize / 1024]
	salt_str := string(RANDOMX_ARGON_SALT)
	argon2_initialize(&instance, key, transmute([]u8)(salt_str), 262144, 3, 1)
	argon2_fill_memory_blocks(&instance)

	gen := blake2_gen_init(key)
	for i in 0 ..< RANDOMX_CACHE_ACCESSES {
		generate_superscalar(&cache.programs[i], &gen)
		for j in 0 ..< int(cache.programs[i].size) {
			if SuperscalarInstructionType(cache.programs[i].program_buffer[j].opcode) == .IMUL_RCP {
				rcp := randomx_reciprocal(cache.programs[i].program_buffer[j].imm32)
				cache.programs[i].program_buffer[j].imm32 = u32(len(cache.reciprocal))
				append(&cache.reciprocal, rcp)
			}
		}
	}
	return cache
}

init_dataset_item :: proc(cache: ^Dataset_Cache, out: []u8, item_number: u64) {
	rl: [8]u64
	register_value := item_number
	rl[0] = (item_number + 1) * SUPERSCALAR_MUL0
	rl[1] = rl[0] ~ SUPERSCALAR_ADD1
	rl[2] = rl[0] ~ SUPERSCALAR_ADD2
	rl[3] = rl[0] ~ SUPERSCALAR_ADD3
	rl[4] = rl[0] ~ SUPERSCALAR_ADD4
	rl[5] = rl[0] ~ SUPERSCALAR_ADD5
	rl[6] = rl[0] ~ SUPERSCALAR_ADD6
	rl[7] = rl[0] ~ SUPERSCALAR_ADD7
	for i in 0 ..< RANDOMX_CACHE_ACCESSES {
		mix := get_mix_block(register_value, cache.memory)
		execute_superscalar(&rl, &cache.programs[i], cache.reciprocal[:])
		for q in 0 ..< 8 {
			rl[q] ~= load64_le(mix[q * 8:])
		}
		register_value = rl[cache.programs[i].addr_reg]
	}
	for q in 0 ..< 8 {
		store64_le(out[q * 8:], rl[q])
	}
}
