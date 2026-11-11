package frostrig_ffi

import core "../core"
import c "core:c"

// Argon2id_Context is the opaque C handle for the Argon2id variant
// module (algo/argon2/argon2_id.c).
Argon2id_Context :: distinct struct {
	_ptr: rawptr,
}

Argon2id_Context_Is_Nil :: proc(ctx: Argon2id_Context) -> bool {
	return ctx._ptr == nil
}

argon2id_create :: proc() -> (Argon2id_Context, core.Error) {
	p := frostrig_argon2id_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Argon2id_Context{_ptr = p}, .None
}

argon2id_destroy :: proc(ctx: Argon2id_Context) {
	if ctx._ptr != nil {
		frostrig_argon2id_destroy(ctx._ptr)
	}
}

argon2id_prepare :: proc(ctx: Argon2id_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_argon2id_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

argon2id_hash :: proc(ctx: Argon2id_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_argon2id_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
