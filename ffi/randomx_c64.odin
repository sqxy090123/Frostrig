package frostrig_ffi

import core "../core"
import c "core:c"

RxC64_Context :: distinct struct {
	_ptr: rawptr,
}

RxC64_Context_Is_Nil :: proc(ctx: RxC64_Context) -> bool {
	return ctx._ptr == nil
}

rxc64_optimal_flags :: proc() -> c.int {
	return frostrig_rx_c64_optimal_flags()
}

rxc64_create :: proc(flags: c.int, key: []u8) -> (RxC64_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx_c64_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return RxC64_Context{_ptr = p}, .None
}

rxc64_destroy :: proc(ctx: RxC64_Context) {
	if ctx._ptr != nil {
		frostrig_rx_c64_destroy(ctx._ptr)
	}
}

rxc64_prepare :: proc(ctx: RxC64_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx_c64_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

rxc64_hash :: proc(ctx: RxC64_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx_c64_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
