#+build linux
package frostrig_ffi

import c "core:c"

// C module object files for the randomx variants, compiled from
// algo/randomx/0.c and algo/randomx/wow.c.  The underlying librandomx.a
// is still linked so that the C module's randomx_* symbols resolve.
foreign import rx0_mod "../algo/randomx/0.o"
foreign import rxwow_mod "../algo/randomx/wow.o"
foreign import rx2_mod "../algo/randomx/2.o"
foreign import rxc64_mod "../algo/randomx/c64.o"
foreign import rxv_mod "../algo/randomx/v.o"
foreign import rxxeq_mod "../algo/randomx/xeq.o"
foreign import rxkeva_mod "../algo/keva/keva.o"
foreign import librandomx "../third_party/randomx/lib/linux-x86_64/librandomx.a"
foreign import librandomxkeva "../third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"

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

@(default_calling_convention = "c")
foreign rx2_mod {
	frostrig_rx2_optimal_flags :: proc() -> c.int ---
	frostrig_rx2_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx2_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx2_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx2_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx2_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx2_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx2_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}

@(default_calling_convention = "c")
foreign rxc64_mod {
	frostrig_rx_c64_optimal_flags :: proc() -> c.int ---
	frostrig_rx_c64_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx_c64_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx_c64_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx_c64_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_c64_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx_c64_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_c64_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}

@(default_calling_convention = "c")
foreign rxv_mod {
	frostrig_rx_v_optimal_flags :: proc() -> c.int ---
	frostrig_rx_v_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx_v_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx_v_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx_v_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_v_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx_v_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_v_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}

@(default_calling_convention = "c")
foreign rxxeq_mod {
	frostrig_rx_xeq_optimal_flags :: proc() -> c.int ---
	frostrig_rx_xeq_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx_xeq_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx_xeq_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx_xeq_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_xeq_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx_xeq_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_xeq_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}

@(default_calling_convention = "c")
foreign rxkeva_mod {
	frostrig_rx_keva_optimal_flags :: proc() -> c.int ---
	frostrig_rx_keva_create        :: proc(flags: c.int, key: rawptr, key_size: c.size_t) -> rawptr ---
	frostrig_rx_keva_destroy       :: proc(ctx: rawptr) ---
	frostrig_rx_keva_prepare       :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_rx_keva_hash          :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_keva_hash_first    :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t) -> c.int ---
	frostrig_rx_keva_hash_next     :: proc(ctx: rawptr, next_input: rawptr, next_input_size: c.size_t, output: rawptr) -> c.int ---
	frostrig_rx_keva_hash_last     :: proc(ctx: rawptr, output: rawptr) -> c.int ---
}
