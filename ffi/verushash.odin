package frostrig_ffi

import core "../core"
import c "core:c"

// Vh22_Context is the opaque C handle for the VerusHash 2.2 variant
// (algo/verushash/verushash.cpp, solutionVersion = FROSTRIG_VH_SV2_2 = 4).
Vh22_Context :: distinct struct {
	_ptr: rawptr,
}

// Vh31_Context is the opaque C handle for the VerusHash 3.1 variant
// (algo/verushash/verushash.cpp, solutionVersion = FROSTRIG_VH_SV2_1 = 3).
Vh31_Context :: distinct struct {
	_ptr: rawptr,
}

Vh22_Context_Is_Nil :: proc(ctx: Vh22_Context) -> bool {
	return ctx._ptr == nil
}

Vh31_Context_Is_Nil :: proc(ctx: Vh31_Context) -> bool {
	return ctx._ptr == nil
}

// --- Vh22 (vh/2.2) ---

vh22_create :: proc() -> (Vh22_Context, core.Error) {
	p := frostrig_verushash_v22_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Vh22_Context{_ptr = p}, .None
}

vh22_destroy :: proc(ctx: Vh22_Context) {
	if ctx._ptr != nil {
		frostrig_verushash_v22_destroy(ctx._ptr)
	}
}

vh22_prepare :: proc(ctx: Vh22_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_verushash_v22_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

vh22_hash :: proc(ctx: Vh22_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_verushash_v22_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// --- Vh31 (vh/3.1) ---

vh31_create :: proc() -> (Vh31_Context, core.Error) {
	p := frostrig_verushash_v31_create()
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Vh31_Context{_ptr = p}, .None
}

vh31_destroy :: proc(ctx: Vh31_Context) {
	if ctx._ptr != nil {
		frostrig_verushash_v31_destroy(ctx._ptr)
	}
}

vh31_prepare :: proc(ctx: Vh31_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_verushash_v31_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

vh31_hash :: proc(ctx: Vh31_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_verushash_v31_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
