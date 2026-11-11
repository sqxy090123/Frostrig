#+build windows
package frostrig_ffi

import c "core:c"

// VerusHash C++ modules (combined): algo/verushash/verushash_all.lib
// Links verushash.obj + vh_clhash_portable.obj + vh_hash.obj + haraka_portable.obj.
foreign import verushash_mod "../algo/verushash/verushash_all.lib"

@(default_calling_convention = "c")
foreign verushash_mod {
	frostrig_vh_force_link      :: proc() ---

	frostrig_verushash_v22_create   :: proc() -> rawptr ---
	frostrig_verushash_v22_destroy  :: proc(ctx: rawptr) ---
	frostrig_verushash_v22_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_verushash_v22_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---

	frostrig_verushash_v31_create   :: proc() -> rawptr ---
	frostrig_verushash_v31_destroy  :: proc(ctx: rawptr) ---
	frostrig_verushash_v31_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_verushash_v31_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
}
