package frostrig_ffi

import core "../core"
import c "core:c"

// RxKeva_Context is the opaque C handle for the RandomX "keva" (Keva)
// variant module (algo/keva/keva.c).  This module links against the
// Keva-patched librandomx-keva.a (different scratchpad / salt constants),
// separate from the shared librandomx.a used by the other 6 RandomX
// variants.
RxKeva_Context :: distinct struct {
	_ptr: rawptr,
}

RxKeva_Context_Is_Nil :: proc(ctx: RxKeva_Context) -> bool {
	return ctx._ptr == nil
}

rxkeva_optimal_flags :: proc() -> c.int {
	return frostrig_rx_keva_optimal_flags()
}

rxkeva_create :: proc(flags: c.int, key: []u8) -> (RxKeva_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx_keva_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return RxKeva_Context{_ptr = p}, .None
}

rxkeva_destroy :: proc(ctx: RxKeva_Context) {
	if ctx._ptr != nil {
		frostrig_rx_keva_destroy(ctx._ptr)
	}
}

rxkeva_prepare :: proc(ctx: RxKeva_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx_keva_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

rxkeva_hash :: proc(ctx: RxKeva_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx_keva_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
