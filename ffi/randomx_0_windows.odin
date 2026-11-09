#+build windows
package frostrig_ffi

import c "core:c"

foreign import rx0_mod "../algo/randomx/0.o"
foreign import rxwow_mod "../algo/randomx/wow.o"
foreign import librandomx "../third_party/randomx/lib/windows-x86_64/librandomx.lib"

@(default_calling_convention = "c")
foreign rx0_mod {
	frostrig_rx0_optimal_flags :: proc() -> c.int ---
	frostrig_rx0_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx0_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx0_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx0_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx0_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx0_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx0_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}

@(default_calling_convention = "c")
foreign rxwow_mod {
	frostrig_rx_wow_optimal_flags :: proc() -> c.int ---
	frostrig_rx_wow_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx_wow_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx_wow_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx_wow_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_wow_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx_wow_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_wow_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}
