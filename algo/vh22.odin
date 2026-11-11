package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_vh22: core.Algo_Id = core.Algo_Id(11)
algo_name_vh22: string = "vh/2.2"
algo_alias_vh22: string = "verushash-v22"

Vh22_Context :: struct {
	ctx: ffi.Vh22_Context,
}

vh22_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.vh22_create()
	if err != .None {
		return {}, err
	}
	c := new(Vh22_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_vh22, ctx = rawptr(c)}, .None
}

vh22_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Vh22_Context) handle.ctx
	ffi.vh22_destroy(c.ctx)
	free(c)
}

vh22_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Vh22_Context) handle.ctx
	return ffi.vh22_prepare(c.ctx, seed)
}

vh22_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Vh22_Context) handle.ctx
	if ffi.Vh22_Context_Is_Nil(c.ctx) {
		return core.Error.Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return core.Error.Invalid_Argument
	}
	nb := to_le_bytes(nonce)

	if len(input)+8 <= HASH_STACK_IN {
		buf: [HASH_STACK_IN]u8
		copy(buf[:len(input)], input)
		for i in 0 ..< 8 {
			buf[len(input)+i] = nb[i]
		}
		out: [HASH_STACK_OUT]u8
		err := ffi.vh22_hash(c.ctx, buf[:len(input)+8], out[:])
		if err != .None {
			return err
		}
		for i in 0 ..< 32 {
			output.bytes[i] = out[i]
		}
		output.len = 32
		return .None
	}

	d_buf := make([dynamic]u8, len(input)+8)
	copy(d_buf[:len(input)], input)
	for i in 0 ..< 8 {
		d_buf[len(input)+i] = nb[i]
	}
	out := make([dynamic]u8, 32)
	err := ffi.vh22_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// VerusHash 2.2 working set: 8480 B key buffer + 8 KiB Haraka scratch.
vh22_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_vh22,
	name   = algo_name_vh22,
	alias  = algo_alias_vh22,
	memory = 64 * 1024,
	create = vh22_create,
	destroy = vh22_destroy,
	prepare = vh22_prepare,
	hash   = vh22_hash,
}
