package frostrig_ffi

import core "../core"
import c "core:c"

RxXeq_Context :: distinct struct {
	_ptr: rawptr,
}

RxXeq_Context_Is_Nil :: proc(ctx: RxXeq_Context) -> bool {
	return ctx._ptr == nil
}

rxxeq_optimal_flags :: proc() -> c.int {
	return frostrig_rx_xeq_optimal_flags()
}

rxxeq_create :: proc(flags: c.int, key: []u8) -> (RxXeq_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx_xeq_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return RxXeq_Context{_ptr = p}, .None
}

rxxeq_destroy :: proc(ctx: RxXeq_Context) {
	if ctx._ptr != nil {
		frostrig_rx_xeq_destroy(ctx._ptr)
	}
}

rxxeq_prepare :: proc(ctx: RxXeq_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx_xeq_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

rxxeq_hash :: proc(ctx: RxXeq_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx_xeq_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
