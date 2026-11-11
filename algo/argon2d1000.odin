package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_argon2d1000: core.Algo_Id = core.Algo_Id(10)
algo_name_argon2d1000: string = "argon2d/1000"
algo_alias_argon2d1000: string = "argon2d1000"

Argon2d1000_Context :: struct {
	ctx: ffi.Argon2d_1000_Context,
}

argon2d1000_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.argon2d1000_create()
	if err != .None {
		return {}, err
	}
	c := new(Argon2d1000_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_argon2d1000, ctx = rawptr(c)}, .None
}

argon2d1000_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Argon2d1000_Context) handle.ctx
	ffi.argon2d1000_destroy(c.ctx)
	free(c)
}

argon2d1000_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2d1000_Context) handle.ctx
	return ffi.argon2d1000_prepare(c.ctx, seed)
}

argon2d1000_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2d1000_Context) handle.ctx
	if ffi.Argon2d_1000_Context_Is_Nil(c.ctx) {
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
	err := ffi.argon2d1000_hash(c.ctx, buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// Argon2d 1000 KiB cache + ~1 MiB temp buffer.
argon2d1000_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_argon2d1000,
	name   = algo_name_argon2d1000,
	alias  = algo_alias_argon2d1000,
	memory = 2 * 1024 * 1024,
	create = argon2d1000_create,
	destroy = argon2d1000_destroy,
	prepare = argon2d1000_prepare,
	hash   = argon2d1000_hash,
}
