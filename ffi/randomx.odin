package frostrig_ffi

import core "../core"

rx_cache_create :: proc(flags: Rx_Flags, key: []u8) -> (Rx_Cache, core.Error) {
	_ = flags
	_ = key
	return {}, .Not_Implemented
}

rx_cache_destroy :: proc(cache: Rx_Cache) {
	_ = cache
}

rx_dataset_create :: proc(flags: Rx_Flags, cache: Rx_Cache) -> (Rx_Dataset, core.Error) {
	_ = flags
	_ = cache
	return {}, .Not_Implemented
}

rx_dataset_destroy :: proc(dataset: Rx_Dataset) {
	_ = dataset
}

rx_vm_create :: proc(flags: Rx_Flags, cache: Rx_Cache, dataset: Rx_Dataset) -> (Rx_Vm, core.Error) {
	_ = flags
	_ = cache
	_ = dataset
	return {}, .Not_Implemented
}

rx_vm_destroy :: proc(vm: Rx_Vm) {
	_ = vm
}

rx_vm_set_cache :: proc(vm: Rx_Vm, cache: Rx_Cache) -> core.Error {
	if rx_vm_is_nil(vm) || rx_cache_is_nil(cache) {
		return .Ffi_Handle_Invalid
	}
	return .Not_Implemented
}

rx_vm_calculate :: proc(vm: Rx_Vm, input: []u8, output: []u8) -> core.Error {
	if rx_vm_is_nil(vm) {
		return .Ffi_Handle_Invalid
	}
	_ = input
	_ = output
	return .Not_Implemented
}
