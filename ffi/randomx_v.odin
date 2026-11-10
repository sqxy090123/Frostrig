package frostrig_ffi

import core "../core"
import c "core:c"

RxV_Context :: distinct struct {
	_ptr: rawptr,
}

RxV_Context_Is_Nil :: proc(ctx: RxV_Context) -> bool {
	return ctx._ptr == nil
}

rxv_optimal_flags :: proc() -> c.int {
	return frostrig_rx_v_optimal_flags()
}

rxv_create :: proc(flags: c.int, key: []u8) -> (RxV_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx_v_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return RxV_Context{_ptr = p}, .None
}

rxv_destroy :: proc(ctx: RxV_Context) {
	if ctx._ptr != nil {
		frostrig_rx_v_destroy(ctx._ptr)
	}
}

rxv_prepare :: proc(ctx: RxV_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx_v_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

rxv_hash :: proc(ctx: RxV_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx_v_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
