package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_argon2id: core.Algo_Id = core.Algo_Id(8)
algo_name_argon2id: string = "argon2id"
algo_alias_argon2id: string = "argon2-id"

Argon2id_Context :: struct {
	ctx: ffi.Argon2id_Context,
}

argon2id_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.argon2id_create()
	if err != .None {
		return {}, err
	}
	c := new(Argon2id_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_argon2id, ctx = rawptr(c)}, .None
}

argon2id_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Argon2id_Context) handle.ctx
	ffi.argon2id_destroy(c.ctx)
	free(c)
}

argon2id_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2id_Context) handle.ctx
	return ffi.argon2id_prepare(c.ctx, seed)
}

argon2id_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2id_Context) handle.ctx
	if ffi.Argon2id_Context_Is_Nil(c.ctx) {
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
		err := ffi.argon2id_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.argon2id_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// Argon2id working set: m_cost=512 KiB cache + 1 MiB temp buffer.
argon2id_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_argon2id,
	name   = algo_name_argon2id,
	alias  = algo_alias_argon2id,
	memory = 4 * 1024 * 1024,
	create = argon2id_create,
	destroy = argon2id_destroy,
	prepare = argon2id_prepare,
	hash   = argon2id_hash,
}
