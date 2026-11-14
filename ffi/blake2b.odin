package frostrig_ffi

import core "../core"
import c "core:c"

// Blake2b_Context is the opaque C handle for the BLAKE2b variant
// module (algo/blake2b/blake2b.c).
Blake2b_Context :: distinct struct {
	_ptr: rawptr,
}

Blake2b_Context_Is_Nil :: proc(ctx: Blake2b_Context) -> bool {
	return ctx._ptr == nil
}

blake2b_create :: proc() -> (Blake2b_Context, core.Error) {
	p := frostrig_blake2b_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Blake2b_Context{_ptr = p}, .None
}

blake2b_destroy :: proc(ctx: Blake2b_Context) {
	if ctx._ptr != nil {
		frostrig_blake2b_destroy(ctx._ptr)
	}
}

blake2b_prepare :: proc(ctx: Blake2b_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_blake2b_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

blake2b_hash :: proc(ctx: Blake2b_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_blake2b_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
