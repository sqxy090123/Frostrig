package frostrig_ffi

import core "../core"
import c "core:c"

// Cn_Pico_Context is the opaque C handle for CryptoNight Pico.
Cn_Pico_Context :: distinct struct {
	_ptr: rawptr,
}

// Cn_Heavy_Context is the opaque C handle for CryptoNight Heavy.
Cn_Heavy_Context :: distinct struct {
	_ptr: rawptr,
}

Cn_Pico_Context_Is_Nil :: proc(ctx: Cn_Pico_Context) -> bool {
	return ctx._ptr == nil
}

Cn_Heavy_Context_Is_Nil :: proc(ctx: Cn_Heavy_Context) -> bool {
	return ctx._ptr == nil
}

// --- CN Pico ---

cn_pico_create :: proc() -> (Cn_Pico_Context, core.Error) {
	p := frostrig_cn_create_pico()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Cn_Pico_Context{_ptr = p}, .None
}

cn_pico_destroy :: proc(ctx: Cn_Pico_Context) {
	if ctx._ptr != nil {
		frostrig_cn_destroy_pico(ctx._ptr)
	}
}

cn_pico_prepare :: proc(ctx: Cn_Pico_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_cn_prepare_pico(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

cn_pico_hash :: proc(ctx: Cn_Pico_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_cn_hash_pico(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// --- CN Heavy ---

cn_heavy_create :: proc() -> (Cn_Heavy_Context, core.Error) {
	p := frostrig_cn_create_heavy()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Cn_Heavy_Context{_ptr = p}, .None
}

cn_heavy_destroy :: proc(ctx: Cn_Heavy_Context) {
	if ctx._ptr != nil {
		frostrig_cn_destroy_heavy(ctx._ptr)
	}
}

cn_heavy_prepare :: proc(ctx: Cn_Heavy_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_cn_prepare_heavy(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

cn_heavy_hash :: proc(ctx: Cn_Heavy_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_cn_hash_heavy(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
