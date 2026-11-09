#+build linux
package frostrig_ffi

import c "core:c"

foreign import librandomx "../third_party/randomx/lib/linux-x86_64/librandomx.a"

@(default_calling_convention = "c")
foreign librandomx {
	randomx_get_flags        :: proc() -> c.int ---
	randomx_alloc_cache      :: proc(flags: c.int) -> rawptr ---
	randomx_init_cache       :: proc(cache: rawptr, key: rawptr, key_size: c.size_t) ---
	randomx_release_cache    :: proc(cache: rawptr) ---
	randomx_alloc_dataset    :: proc(flags: c.int) -> rawptr ---
	randomx_release_dataset  :: proc(dataset: rawptr) ---
	randomx_dataset_item_count :: proc() -> c.ulong ---
	randomx_init_dataset     :: proc(dataset: rawptr, cache: rawptr, start_item: c.ulong, item_count: c.ulong) ---
	randomx_create_vm        :: proc(flags: c.int, cache: rawptr, dataset: rawptr) -> rawptr ---
	randomx_destroy_vm       :: proc(vm: rawptr) ---
	randomx_vm_set_cache     :: proc(vm: rawptr, cache: rawptr) ---
	randomx_vm_set_dataset   :: proc(vm: rawptr, dataset: rawptr) ---
	randomx_calculate_hash   :: proc(vm: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) ---
	randomx_calculate_hash_first :: proc(vm: rawptr, input: rawptr, input_size: c.size_t) ---
	randomx_calculate_hash_next  :: proc(vm: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) ---
	randomx_calculate_hash_last  :: proc(vm: rawptr, output: rawptr) ---
	randomx_calculate_commitment :: proc(input: rawptr, input_size: c.size_t, hash_in: rawptr, com_out: rawptr) ---
}
