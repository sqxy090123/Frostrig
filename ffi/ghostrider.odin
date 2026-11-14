package frostrig_ffi

import core "../core"
import c "core:c"

// Ghostrider_Context is the opaque C handle for the GhostRider
// chameleon hash module (algo/ghostrider/ghostrider.c).
Ghostrider_Context :: distinct struct {
	_ptr: rawptr,
}

Ghostrider_Context_Is_Nil :: proc(ctx: Ghostrider_Context) -> bool {
	return ctx._ptr == nil
}

ghostrider_create :: proc() -> (Ghostrider_Context, core.Error) {
	p := frostrig_ghostrider_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Ghostrider_Context{_ptr = p}, .None
}

ghostrider_destroy :: proc(ctx: Ghostrider_Context) {
	if ctx._ptr != nil {
		frostrig_ghostrider_destroy(ctx._ptr)
	}
}

ghostrider_prepare :: proc(ctx: Ghostrider_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_ghostrider_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

ghostrider_hash :: proc(ctx: Ghostrider_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_ghostrider_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
