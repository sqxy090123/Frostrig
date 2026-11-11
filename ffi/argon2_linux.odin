#+build linux
package frostrig_ffi

import c "core:c"

// Argon2 variant modules (combined): algo/argon2/argon2_all.o
// Links argon2.o + core.o + opt.o + blake2b.o + argon2_id.o + argon2d.o.
// opt.o provides fill_segment (AVX2/SSE path); ref.o dropped to avoid
// duplicate fill_segment export.
foreign import argon2_mod "../algo/argon2/argon2_all.o"

@(default_calling_convention = "c")
foreign argon2_mod {
	frostrig_argon2id_create   :: proc() -> rawptr ---
	frostrig_argon2id_destroy  :: proc(ctx: rawptr) ---
	frostrig_argon2id_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_argon2id_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---

	frostrig_argon2d16000_create   :: proc() -> rawptr ---
	frostrig_argon2d16000_destroy  :: proc(ctx: rawptr) ---
	frostrig_argon2d16000_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_argon2d16000_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---

	frostrig_argon2d1000_create   :: proc() -> rawptr ---
	frostrig_argon2d1000_destroy  :: proc(ctx: rawptr) ---
	frostrig_argon2d1000_prepare  :: proc(ctx: rawptr, key: rawptr, key_size: c.size_t) -> c.int ---
	frostrig_argon2d1000_hash     :: proc(ctx: rawptr, input: rawptr, input_size: c.size_t, output: rawptr) -> c.int ---
}
