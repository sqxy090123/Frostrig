package frostrig_ffi

import core "../core"
import c "core:c"

randomx_flag_default:     c.int = 0
randomx_flag_large_pages: c.int = 1
randomx_flag_hard_aes:    c.int = 2
randomx_flag_full_mem:    c.int = 4
randomx_flag_jit:         c.int = 8
randomx_flag_secure:      c.int = 16
randomx_flag_argon2_ssse3: c.int = 32
randomx_flag_argon2_avx2:  c.int = 64
randomx_flag_v2:          c.int = 128

randomx_hash_size: c.size_t = 32

// raw_flags converts an Odin Rx_Flags bitmask to the C c.int randomx_flags
// value expected by every foreign randomx_* proc.  The bit values match the
// RANDOMX_FLAG_* constants in src/randomx.h.
raw_flags :: proc(flags: Rx_Flags) -> c.int {
	return c.int(u32(flags))
}

// data_of returns the raw C pointer backing a []u8 slice.  An empty
// slice yields nil.
data_of :: proc(s: []u8) -> rawptr {
	if len(s) == 0 {
		return nil
	}
	return &s[0]
}

// get_optimal_flags returns the C-side recommended flags for the current
// machine (JIT + HARD_AES + ARGON2_* auto-detected by randomx_get_flags).
// Large_Pages, Full_Mem, and Secure are not auto-returned; callers add
// them to the returned value when appropriate.
get_optimal_flags :: proc() -> c.int {
	return randomx_get_flags()
}

rx_cache_create :: proc(flags: Rx_Flags, key: []u8) -> (Rx_Cache, core.Error) {
	c_flags := raw_flags(flags)
	p := randomx_alloc_cache(c_flags)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	if len(key) > 0 {
		randomx_init_cache(p, data_of(key), c.size_t(len(key)))
	}
	return Rx_Cache{_ptr = p}, .None
}

rx_cache_destroy :: proc(cache: Rx_Cache) {
	if cache._ptr != nil {
		randomx_release_cache(cache._ptr)
	}
}

rx_dataset_create :: proc(flags: Rx_Flags, cache: Rx_Cache) -> (Rx_Dataset, core.Error) {
	if rx_cache_is_nil(cache) {
		return {}, .Ffi_Handle_Invalid
	}
	c_flags := raw_flags(flags)
	p := randomx_alloc_dataset(c_flags)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	count := randomx_dataset_item_count()
	randomx_init_dataset(p, cache._ptr, 0, count)
	return Rx_Dataset{_ptr = p}, .None
}

rx_dataset_destroy :: proc(dataset: Rx_Dataset) {
	if dataset._ptr != nil {
		randomx_release_dataset(dataset._ptr)
	}
}

rx_vm_create :: proc(flags: Rx_Flags, cache: Rx_Cache, dataset: Rx_Dataset) -> (Rx_Vm, core.Error) {
	c_flags := raw_flags(flags)
	cache_ptr := rawptr(nil)
	if cache._ptr != nil {
		cache_ptr = cache._ptr
	}
	dataset_ptr := rawptr(nil)
	if dataset._ptr != nil {
		dataset_ptr = dataset._ptr
	}
	p := randomx_create_vm(c_flags, cache_ptr, dataset_ptr)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Rx_Vm{_ptr = p}, .None
}

rx_vm_destroy :: proc(vm: Rx_Vm) {
	if vm._ptr != nil {
		randomx_destroy_vm(vm._ptr)
	}
}

rx_vm_set_cache :: proc(vm: Rx_Vm, cache: Rx_Cache) -> core.Error {
	if rx_vm_is_nil(vm) || rx_cache_is_nil(cache) {
		return .Ffi_Handle_Invalid
	}
	randomx_vm_set_cache(vm._ptr, cache._ptr)
	return .None
}

rx_vm_set_dataset :: proc(vm: Rx_Vm, dataset: Rx_Dataset) -> core.Error {
	if rx_vm_is_nil(vm) || rx_dataset_is_nil(dataset) {
		return .Ffi_Handle_Invalid
	}
	randomx_vm_set_dataset(vm._ptr, dataset._ptr)
	return .None
}

// rx_vm_calculate computes a single RandomX hash.  input must be the
// concatenated block blob + nonce; output must hold at least 32 bytes
// (randomx_hash_size).
rx_vm_calculate :: proc(vm: Rx_Vm, input: []u8, output: []u8) -> core.Error {
	if rx_vm_is_nil(vm) {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < int(randomx_hash_size) {
		return .Invalid_Argument
	}
	randomx_calculate_hash(
		vm._ptr,
		data_of(input),
		c.size_t(len(input)),
		data_of(output),
	)
	return .None
}

// rx_vm_calculate_first starts a pipelined hash on vm.  Call
// rx_vm_calculate_next for each subsequent input, then
// rx_vm_calculate_last to drain the final hash.  The pipeline avoids
// re-initialising the scratchpad between hashes and is what XMrig uses
// for multi-hash workloads.
rx_vm_calculate_first :: proc(vm: Rx_Vm, input: []u8) -> core.Error {
	if rx_vm_is_nil(vm) {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return .Invalid_Argument
	}
	randomx_calculate_hash_first(vm._ptr, data_of(input), c.size_t(len(input)))
	return .None
}

rx_vm_calculate_next :: proc(vm: Rx_Vm, input: []u8, output: []u8) -> core.Error {
	if rx_vm_is_nil(vm) {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < int(randomx_hash_size) {
		return .Invalid_Argument
	}
	randomx_calculate_hash_next(
		vm._ptr,
		data_of(input),
		c.size_t(len(input)),
		data_of(output),
	)
	return .None
}

rx_vm_calculate_last :: proc(vm: Rx_Vm, output: []u8) -> core.Error {
	if rx_vm_is_nil(vm) {
		return .Ffi_Handle_Invalid
	}
	if len(output) < int(randomx_hash_size) {
		return .Invalid_Argument
	}
	randomx_calculate_hash_last(vm._ptr, data_of(output))
	return .None
}

// rx_calculate_commitment produces a Monero v2 commitment: blake2b(input
// || hash_in) -> 32 bytes.  hash_in is the 32-byte output of
// rx_vm_calculate* (RANDOMX_HASH_SIZE).
rx_calculate_commitment :: proc(input: []u8, hash_in: []u8, com_out: []u8) -> core.Error {
	if len(hash_in) < int(randomx_hash_size) || len(com_out) < int(randomx_hash_size) {
		return .Invalid_Argument
	}
	randomx_calculate_commitment(
		data_of(input),
		c.size_t(len(input)),
		data_of(hash_in),
		data_of(com_out),
	)
	return .None
}
