package frostrig_ffi

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
	Large_Pages,
	Hard_Aes,
	Full_Mem,
	Jit,
	Secure,
	Argon2_Ssse3,
	Argon2_Avx2,
}

Rx_Flags :: distinct bit_set[Rx_Flag; u32]

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
