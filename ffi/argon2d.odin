package frostrig_ffi

import core "../core"
import c "core:c"

// Argon2d_Context is the opaque C handle for the Argon2d variants
// (algo/argon2/argon2d.c).  Two parameter sets are exposed:
// Argon2d_16000 (m=16000 KiB) and Argon2d_1000 (m=1000 KiB).
Argon2d_16000_Context :: distinct struct {
	_ptr: rawptr,
}

Argon2d_1000_Context :: distinct struct {
	_ptr: rawptr,
}

Argon2d_16000_Context_Is_Nil :: proc(ctx: Argon2d_16000_Context) -> bool {
	return ctx._ptr == nil
}

Argon2d_1000_Context_Is_Nil :: proc(ctx: Argon2d_1000_Context) -> bool {
	return ctx._ptr == nil
}

// --- Argon2d_16000 ---

argon2d16000_create :: proc() -> (Argon2d_16000_Context, core.Error) {
	p := frostrig_argon2d16000_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Argon2d_16000_Context{_ptr = p}, .None
}

argon2d16000_destroy :: proc(ctx: Argon2d_16000_Context) {
	if ctx._ptr != nil {
		frostrig_argon2d16000_destroy(ctx._ptr)
	}
}

argon2d16000_prepare :: proc(ctx: Argon2d_16000_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_argon2d16000_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

argon2d16000_hash :: proc(ctx: Argon2d_16000_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_argon2d16000_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// --- Argon2d_1000 ---

argon2d1000_create :: proc() -> (Argon2d_1000_Context, core.Error) {
	p := frostrig_argon2d1000_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Argon2d_1000_Context{_ptr = p}, .None
}

argon2d1000_destroy :: proc(ctx: Argon2d_1000_Context) {
	if ctx._ptr != nil {
		frostrig_argon2d1000_destroy(ctx._ptr)
	}
}

argon2d1000_prepare :: proc(ctx: Argon2d_1000_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_argon2d1000_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

argon2d1000_hash :: proc(ctx: Argon2d_1000_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_argon2d1000_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
