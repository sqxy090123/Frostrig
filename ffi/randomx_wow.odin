package frostrig_ffi

import core "../core"
import c "core:c"

// RxWow_Context is the opaque C handle for the RandomX "wow" (V2) variant
// module (algo/randomx/wow.c).
RxWow_Context :: distinct struct {
	_ptr: rawptr,
}

RxWow_Context_Is_Nil :: proc(ctx: RxWow_Context) -> bool {
	return ctx._ptr == nil
}

// rxwow_optimal_flags returns the C-side recommended flags for the wow
// variant (includes the V2 bit in addition to machine-optimal flags).
rxwow_optimal_flags :: proc() -> c.int {
	return frostrig_rx_wow_optimal_flags()
}

// rxwow_create initialises a RandomX wow-variant context.
rxwow_create :: proc(flags: c.int, key: []u8) -> (RxWow_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx_wow_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return RxWow_Context{_ptr = p}, .None
}

// rxwow_destroy releases all resources owned by the wow C context.
rxwow_destroy :: proc(ctx: RxWow_Context) {
	if ctx._ptr != nil {
		frostrig_rx_wow_destroy(ctx._ptr)
	}
}

// rxwow_prepare (re)seeds the cache with a new key.
rxwow_prepare :: proc(ctx: RxWow_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx_wow_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// rxwow_hash computes one RandomX wow-variant hash.
rxwow_hash :: proc(ctx: RxWow_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx_wow_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
