package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_blake2b: core.Algo_Id = core.Algo_Id(13)
algo_name_blake2b: string = "blake2b"
algo_alias_blake2b: string = "blake2"

Blake2b_Algo_Context :: struct {
	ctx: ffi.Blake2b_Context,
}

blake2b_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.blake2b_create()
	if err != .None {
		return {}, err
	}
	c := new(Blake2b_Algo_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_blake2b, ctx = rawptr(c)}, .None
}

blake2b_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Blake2b_Algo_Context) handle.ctx
 ffi.blake2b_destroy(c.ctx)
	free(c)
}

blake2b_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Blake2b_Algo_Context) handle.ctx
	return ffi.blake2b_prepare(c.ctx, seed)
}

blake2b_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Blake2b_Algo_Context) handle.ctx
	if ffi.Blake2b_Context_Is_Nil(c.ctx) {
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
		err := ffi.blake2b_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.blake2b_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// BLAKE2b is stateless and has a tiny memory footprint.
blake2b_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_blake2b,
	name     = algo_name_blake2b,
	alias    = algo_alias_blake2b,
	memory   = 0,
	create   = blake2b_create,
	destroy  = blake2b_destroy,
	prepare  = blake2b_prepare,
	hash     = blake2b_hash,
}
