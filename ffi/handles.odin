package frostrig_ffi

import c "core:c"

Rx_Cache :: distinct struct {
	_ptr: rawptr,
}

Rx_Dataset :: distinct struct {
	_ptr: rawptr,
}

Rx_Vm :: distinct struct {
	_ptr: rawptr,
}

Rx_Flag :: enum u32 {
	Large_Pages  = 1,
	Hard_Aes     = 2,
	Full_Mem     = 4,
	Jit          = 8,
	Secure       = 16,
	Argon2_Ssse3 = 32,
	Argon2_Avx2  = 64,
	Argon2       = 96,
	V2           = 128,
}

Rx_Flags :: distinct u32

rx_default_flags: Rx_Flags = 0

// rx_get_optimal_flags returns the C-side recommended flags for the current
// machine (JIT + HARD_AES + ARGON2 auto-detected by randomx_get_flags).
rx_get_optimal_flags :: proc() -> Rx_Flags {
	return Rx_Flags(u32(get_optimal_flags()))
}

// rx_or combines two flag sets.
rx_or :: proc(a: Rx_Flags, b: Rx_Flags) -> Rx_Flags {
	return Rx_Flags(u32(a) | u32(b))
}

// rx_has reports whether flag `b` is present in `a`.
rx_has :: proc(a: Rx_Flags, b: Rx_Flags) -> bool {
	return (u32(a) & u32(b)) != 0
}

rx_handle_is_nil :: proc {
	rx_cache_is_nil,
	rx_dataset_is_nil,
	rx_vm_is_nil,
}

rx_cache_is_nil :: proc(cache: Rx_Cache) -> bool {
	return cache._ptr == nil
}

rx_dataset_is_nil :: proc(dataset: Rx_Dataset) -> bool {
	return dataset._ptr == nil
}

rx_vm_is_nil :: proc(vm: Rx_Vm) -> bool {
	return vm._ptr == nil
}
