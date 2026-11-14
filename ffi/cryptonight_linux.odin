#+build linux
package frostrig_ffi

import c "core:c"

foreign import cn_mod "../algo/cryptonight/cryptonight.o"

@(default_calling_convention = "c")
foreign cn_mod {
	frostrig_cn_create_pico   :: proc() -> rawptr ---
	frostrig_cn_destroy_pico  :: proc(ctx: rawptr) ---
	frostrig_cn_prepare_pico  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_cn_hash_pico     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---

	frostrig_cn_create_heavy   :: proc() -> rawptr ---
	frostrig_cn_destroy_heavy  :: proc(ctx: rawptr) ---
	frostrig_cn_prepare_heavy  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_cn_hash_heavy     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
}
