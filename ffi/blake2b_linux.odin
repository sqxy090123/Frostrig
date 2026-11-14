#+build linux
package frostrig_ffi

import c "core:c"

foreign import blake2b_mod "../algo/blake2b/blake2b.o"

@(default_calling_convention = "c")
foreign blake2b_mod {
	frostrig_blake2b_create   :: proc() -> rawptr ---
	frostrig_blake2b_destroy  :: proc(ctx: rawptr) ---
	frostrig_blake2b_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_blake2b_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
}
