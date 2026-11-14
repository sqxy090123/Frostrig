#+build windows
package frostrig_ffi

import c "core:c"

foreign import gr_mod "../algo/ghostrider/ghostrider.obj"

@(default_calling_convention = "c")
foreign gr_mod {
	frostrig_ghostrider_create   :: proc() -> rawptr ---
	frostrig_ghostrider_destroy  :: proc(ctx: rawptr) ---
	frostrig_ghostrider_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_ghostrider_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
}
