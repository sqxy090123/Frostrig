package frostrig_ffi

import core "../core"
import c "core:c"

Rx2_Context :: distinct struct {
	_ptr: rawptr,
}

Rx2_Context_Is_Nil :: proc(ctx: Rx2_Context) -> bool {
	return ctx._ptr == nil
}

rx2_optimal_flags :: proc() -> c.int {
	return frostrig_rx2_optimal_flags()
}

rx2_create :: proc(flags: c.int, key: []u8) -> (Rx2_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx2_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Rx2_Context{_ptr = p}, .None
}

rx2_destroy :: proc(ctx: Rx2_Context) {
	if ctx._ptr != nil {
		frostrig_rx2_destroy(ctx._ptr)
	}
}

rx2_prepare :: proc(ctx: Rx2_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx2_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

rx2_hash :: proc(ctx: Rx2_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx2_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
