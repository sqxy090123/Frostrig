package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_argon2d16000: core.Algo_Id = core.Algo_Id(9)
algo_name_argon2d16000: string = "argon2d/16000"
algo_alias_argon2d16000: string = "argon2d16000"

Argon2d16000_Context :: struct {
	ctx: ffi.Argon2d_16000_Context,
}

argon2d16000_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.argon2d16000_create()
	if err != .None {
		return {}, err
	}
	c := new(Argon2d16000_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_argon2d16000, ctx = rawptr(c)}, .None
}

argon2d16000_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Argon2d16000_Context) handle.ctx
	ffi.argon2d16000_destroy(c.ctx)
	free(c)
}

argon2d16000_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2d16000_Context) handle.ctx
	return ffi.argon2d16000_prepare(c.ctx, seed)
}

argon2d16000_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Argon2d16000_Context) handle.ctx
	if ffi.Argon2d_16000_Context_Is_Nil(c.ctx) {
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
	err := ffi.argon2d16000_hash(c.ctx, buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// Argon2d 16000 KiB cache + ~2 MiB temp buffer.
argon2d16000_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_argon2d16000,
	name   = algo_name_argon2d16000,
	alias  = algo_alias_argon2d16000,
	memory = 18 * 1024 * 1024,
	create = argon2d16000_create,
	destroy = argon2d16000_destroy,
	prepare = argon2d16000_prepare,
	hash   = argon2d16000_hash,
}
