package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_ghostrider: core.Algo_Id = core.Algo_Id(16)
algo_name_ghostrider: string = "ghostrider"
algo_alias_ghostrider: string = "gr"

Ghostrider_Algo_Context :: struct {
	ctx: ffi.Ghostrider_Context,
}

ghostrider_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.ghostrider_create()
	if err != .None {
		return {}, err
	}
	c := new(Ghostrider_Algo_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_ghostrider, ctx = rawptr(c)}, .None
}

ghostrider_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Ghostrider_Algo_Context) handle.ctx
	ffi.ghostrider_destroy(c.ctx)
	free(c)
}

ghostrider_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Ghostrider_Algo_Context) handle.ctx
	return ffi.ghostrider_prepare(c.ctx, seed)
}

ghostrider_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Ghostrider_Algo_Context) handle.ctx
	if ffi.Ghostrider_Context_Is_Nil(c.ctx) {
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
		err := ffi.ghostrider_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.ghostrider_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// GhostRider uses a 1 MiB keystream buffer for the chameleon chain.
ghostrider_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_ghostrider,
	name     = algo_name_ghostrider,
	alias    = algo_alias_ghostrider,
	memory   = 1 * 1024 * 1024,
	create   = ghostrider_create,
	destroy  = ghostrider_destroy,
	prepare  = ghostrider_prepare,
	hash     = ghostrider_hash,
}
