package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_vh31: core.Algo_Id = core.Algo_Id(12)
algo_name_vh31: string = "vh/3.1"
algo_alias_vh31: string = "verushash-v31"

Vh31_Context :: struct {
	ctx: ffi.Vh31_Context,
}

vh31_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.vh31_create()
	if err != .None {
		return {}, err
	}
	c := new(Vh31_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_vh31, ctx = rawptr(c)}, .None
}

vh31_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Vh31_Context) handle.ctx
	ffi.vh31_destroy(c.ctx)
	free(c)
}

vh31_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Vh31_Context) handle.ctx
	return ffi.vh31_prepare(c.ctx, seed)
}

vh31_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Vh31_Context) handle.ctx
	if ffi.Vh31_Context_Is_Nil(c.ctx) {
		return core.Error.Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return core.Error.Invalid_Argument
	}
	buf := make([dynamic]u8, len(input)+8)
	copy(buf[:len(input)], input)
	nonce_bytes := to_le_bytes(nonce)
	for i in 0 ..< 8 {
		buf[len(input)+i] = nonce_bytes[i]
	}
	out := make([dynamic]u8, 32)
	err := ffi.vh31_hash(c.ctx, buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// VerusHash 3.1 working set: 8480 B key buffer + 8 KiB Haraka scratch.
vh31_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_vh31,
	name   = algo_name_vh31,
	alias  = algo_alias_vh31,
	memory = 64 * 1024,
	create = vh31_create,
	destroy = vh31_destroy,
	prepare = vh31_prepare,
	hash   = vh31_hash,
}
