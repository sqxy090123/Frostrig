package frostrig_randomx_odin


ARGON2_BLOCK_SIZE :: 1024
ARGON2_QWORDS_IN_BLOCK :: ARGON2_BLOCK_SIZE / 8
ARGON2_SYNC_POINTS :: 4
ARGON2_PREHASH_DIGEST_LENGTH :: 64
ARGON2_PREHASH_SEED_LENGTH :: 72
ARGON2_VERSION_10 :: 0x10
ARGON2_VERSION_13 :: 0x13
ARGON2_VERSION_NUMBER :: ARGON2_VERSION_13

Block :: [ARGON2_QWORDS_IN_BLOCK]u64

Argon2_Instance :: struct {
	memory:        []Block,
	version:       u32,
	passes:        u32,
	memory_blocks: u32,
	segment_length: u32,
	lane_length:   u32,
	lanes:         u32,
	threads:       u32,
	type:          int, // 0 = Argon2_d
}

Argon2_Position :: struct {
	pass:  u32,
	lane:  u32,
	slice: u8,
	index: u32,
}

fBlaMka :: #force_inline proc(x: u64, y: u64) -> u64 {
	xy := (x & 0xFFFFFFFF) * (y & 0xFFFFFFFF)
	return x + y + 2 * xy
}

blamka_G :: #force_inline proc(a: ^u64, b: ^u64, c: ^u64, d: ^u64) {
	a^ = fBlaMka(a^, b^)
	d^ = rotr64(d^ ~ a^, 32)
	c^ = fBlaMka(c^, d^)
	b^ = rotr64(b^ ~ c^, 24)
	a^ = fBlaMka(a^, b^)
	d^ = rotr64(d^ ~ a^, 16)
	c^ = fBlaMka(c^, d^)
	b^ = rotr64(b^ ~ c^, 63)
}

// BLAKE2_ROUND_NOMSG on 16 u64 lanes
blake2_round_nomsg :: #force_inline proc(v: [^]u64) {
	blamka_G(&v[0], &v[4], &v[8], &v[12])
	blamka_G(&v[1], &v[5], &v[9], &v[13])
	blamka_G(&v[2], &v[6], &v[10], &v[14])
	blamka_G(&v[3], &v[7], &v[11], &v[15])
	blamka_G(&v[0], &v[5], &v[10], &v[15])
	blamka_G(&v[1], &v[6], &v[11], &v[12])
	blamka_G(&v[2], &v[7], &v[8], &v[13])
	blamka_G(&v[3], &v[4], &v[9], &v[14])
}

argon2_index_alpha :: proc(instance: ^Argon2_Instance, position: ^Argon2_Position, pseudo_rand: u32, same_lane: bool) -> u32 {
	reference_area_size: u32
	if position.pass == 0 {
		if position.slice == 0 {
			reference_area_size = position.index - 1
		} else {
			if same_lane {
				reference_area_size = u32(position.slice) * instance.segment_length + position.index - 1
			} else {
				reference_area_size = u32(position.slice) * instance.segment_length + (position.index == 0 ? 0xFFFFFFFF : 0)
			}
		}
	} else {
		if same_lane {
			reference_area_size = instance.lane_length - instance.segment_length + position.index - 1
		} else {
			reference_area_size = instance.lane_length - instance.segment_length + (position.index == 0 ? 0xFFFFFFFF : 0)
		}
	}

	relative_position := u64(pseudo_rand)
	relative_position = relative_position * relative_position >> 32
	relative_position = u64(reference_area_size - 1) - (u64(reference_area_size) * relative_position >> 32)

	start_position: u32 = 0
	if position.pass != 0 {
		start_position = (position.slice == ARGON2_SYNC_POINTS - 1) ? 0 : (u32(position.slice) + 1) * instance.segment_length
	}

	absolute_position := (start_position + u32(relative_position)) % instance.lane_length
	return absolute_position
}

argon2_load_block :: proc(dst: ^Block, input: []u8) {
	for i in 0 ..< ARGON2_QWORDS_IN_BLOCK {
		dst[i] = load64_le(input[i*8:])
	}
}

argon2_fill_block :: proc(prev_block: ^Block, ref_block: ^Block, next_block: ^Block, with_xor: bool) {
	blockR: Block
	block_tmp: Block
	for i in 0 ..< ARGON2_QWORDS_IN_BLOCK {
		blockR[i] = ref_block[i] ~ prev_block[i]
		block_tmp[i] = blockR[i]
	}
	if with_xor {
		for i in 0 ..< ARGON2_QWORDS_IN_BLOCK {
			block_tmp[i] = block_tmp[i] ~ next_block[i]
		}
	}
	// 8 rows of 16 lanes: (0-15), (16-31), ..., (112-127)
	for i in 0 ..< 8 {
		blake2_round_nomsg(raw_data(blockR[16*i:]))
	}
	// 8 rows of 16 lanes interleaved: (0,1,16,17,...), ...
	for i in 0 ..< 8 {
		base := 2 * i
		lanes: [16]u64 = {
			blockR[base], blockR[base + 1], blockR[base + 16], blockR[base + 17],
			blockR[base + 32], blockR[base + 33], blockR[base + 48], blockR[base + 49],
			blockR[base + 64], blockR[base + 65], blockR[base + 80], blockR[base + 81],
			blockR[base + 96], blockR[base + 97], blockR[base + 112], blockR[base + 113],
		}
		blake2_round_nomsg(raw_data(lanes[:]))
		blockR[base] = lanes[0]
		blockR[base + 1] = lanes[1]
		blockR[base + 16] = lanes[2]
		blockR[base + 17] = lanes[3]
		blockR[base + 32] = lanes[4]
		blockR[base + 33] = lanes[5]
		blockR[base + 48] = lanes[6]
		blockR[base + 49] = lanes[7]
		blockR[base + 64] = lanes[8]
		blockR[base + 65] = lanes[9]
		blockR[base + 80] = lanes[10]
		blockR[base + 81] = lanes[11]
		blockR[base + 96] = lanes[12]
		blockR[base + 97] = lanes[13]
		blockR[base + 112] = lanes[14]
		blockR[base + 113] = lanes[15]
	}
	for i in 0 ..< ARGON2_QWORDS_IN_BLOCK {
		next_block[i] = block_tmp[i] ~ blockR[i]
	}
}

argon2_fill_segment_ref :: proc(instance: ^Argon2_Instance, position: Argon2_Position) {
	starting_index: u32 = 0
	if position.pass == 0 && position.slice == 0 {
		starting_index = 2
	}
	curr_offset := position.lane * instance.lane_length + u32(position.slice) * instance.segment_length + starting_index
	prev_offset: u32
	if curr_offset % instance.lane_length == 0 {
		prev_offset = curr_offset + instance.lane_length - 1
	} else {
		prev_offset = curr_offset - 1
	}
	for i in starting_index ..< instance.segment_length {
		if curr_offset % instance.lane_length == 1 {
			prev_offset = curr_offset - 1
		}
		pseudo_rand := instance.memory[prev_offset][0]
		ref_lane := u32(pseudo_rand >> 32) % instance.lanes
		if position.pass == 0 && position.slice == 0 {
			ref_lane = position.lane
		}
		pos := position
		pos.index = i
		ref_index := argon2_index_alpha(instance, &pos, u32(pseudo_rand & 0xFFFFFFFF), ref_lane == position.lane)
		ref_block := &instance.memory[instance.lane_length * ref_lane + ref_index]
		curr_block := &instance.memory[curr_offset]
		with_xor: bool
		if instance.version == ARGON2_VERSION_10 {
			with_xor = false
		} else {
			with_xor = position.pass != 0
		}
		argon2_fill_block(&instance.memory[prev_offset], ref_block, curr_block, with_xor)
		curr_offset += 1
		prev_offset += 1
	}
}

argon2_initial_hash :: proc(blockhash: []u8, lanes: u32, outlen: u32, m_cost: u32, t_cost: u32, version: u32, typ: int, pwd: []u8, salt: []u8, secret: []u8, ad: []u8) {
	BlakeHash: Blake2b_State
	blake2b_init(&BlakeHash, ARGON2_PREHASH_DIGEST_LENGTH)
	value: [4]u8

	store32_le(value[:], lanes)
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], outlen)
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], m_cost)
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], t_cost)
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], version)
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], u32(typ))
	blake2b_update(&BlakeHash, value[:])
	store32_le(value[:], u32(len(pwd)))
	blake2b_update(&BlakeHash, value[:])
	if len(pwd) > 0 {
		blake2b_update(&BlakeHash, pwd)
	}
	store32_le(value[:], u32(len(salt)))
	blake2b_update(&BlakeHash, value[:])
	if len(salt) > 0 {
		blake2b_update(&BlakeHash, salt)
	}
	store32_le(value[:], u32(len(secret)))
	blake2b_update(&BlakeHash, value[:])
	if len(secret) > 0 {
		blake2b_update(&BlakeHash, secret)
	}
	store32_le(value[:], u32(len(ad)))
	blake2b_update(&BlakeHash, value[:])
	if len(ad) > 0 {
		blake2b_update(&BlakeHash, ad)
	}
	blake2b_final(&BlakeHash, blockhash, ARGON2_PREHASH_DIGEST_LENGTH)
}

argon2_fill_first_blocks :: proc(blockhash: []u8, instance: ^Argon2_Instance) {
	blockhash_bytes: [ARGON2_BLOCK_SIZE]u8
	for l in 0 ..< instance.lanes {
		store32_le(blockhash[ARGON2_PREHASH_DIGEST_LENGTH:], 0)
		store32_le(blockhash[ARGON2_PREHASH_DIGEST_LENGTH + 4:], l)
		blake2b_long(blockhash_bytes[:], ARGON2_BLOCK_SIZE, blockhash[:ARGON2_PREHASH_SEED_LENGTH])
		argon2_load_block(&instance.memory[l * instance.lane_length + 0], blockhash_bytes[:])

		store32_le(blockhash[ARGON2_PREHASH_DIGEST_LENGTH:], 1)
		blake2b_long(blockhash_bytes[:], ARGON2_BLOCK_SIZE, blockhash[:ARGON2_PREHASH_SEED_LENGTH])
		argon2_load_block(&instance.memory[l * instance.lane_length + 1], blockhash_bytes[:])
	}
}

// Standard RandomX Argon2d cache init parameters (RANDOMX_ARGON_MEMORY=262144 KiB etc)
argon2_initialize :: proc(instance: ^Argon2_Instance, pwd: []u8, salt: []u8, m_cost: u32, t_cost: u32, lanes: u32) {
	blockhash: [ARGON2_PREHASH_SEED_LENGTH]u8
	instance.version = ARGON2_VERSION_NUMBER
	instance.passes = t_cost
	instance.memory_blocks = m_cost
	instance.segment_length = m_cost / (lanes * ARGON2_SYNC_POINTS)
	instance.lane_length = instance.segment_length * ARGON2_SYNC_POINTS
	instance.lanes = lanes
	instance.threads = 1
	instance.type = 0 // Argon2_d

	argon2_initial_hash(blockhash[:], lanes, 0, m_cost, t_cost, ARGON2_VERSION_NUMBER, 0, pwd, salt, nil, nil)
	argon2_fill_first_blocks(blockhash[:], instance)
}

argon2_fill_memory_blocks :: proc(instance: ^Argon2_Instance) {
	for r in 0 ..< instance.passes {
		for s in 0 ..< ARGON2_SYNC_POINTS {
			for l in 0 ..< instance.lanes {
				position := Argon2_Position{pass = r, lane = l, slice = u8(s), index = 0}
				argon2_fill_segment_ref(instance, position)
			}
		}
	}
}
