package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_cn_heavy: core.Algo_Id = core.Algo_Id(15)
algo_name_cn_heavy: string = "cn-heavy/0"
algo_alias_cn_heavy: string = "cn_heavy"

Cn_Heavy_Context :: struct {
	ctx: ffi.Cn_Heavy_Context,
}

cn_heavy_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.cn_heavy_create()
	if err != .None {
		return {}, err
	}
	c := new(Cn_Heavy_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_cn_heavy, ctx = rawptr(c)}, .None
}

cn_heavy_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Cn_Heavy_Context) handle.ctx
	ffi.cn_heavy_destroy(c.ctx)
	free(c)
}

cn_heavy_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Cn_Heavy_Context) handle.ctx
	return ffi.cn_heavy_prepare(c.ctx, seed)
}

cn_heavy_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Cn_Heavy_Context) handle.ctx
	if ffi.Cn_Heavy_Context_Is_Nil(c.ctx) {
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
		err := ffi.cn_heavy_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.cn_heavy_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// CryptoNight Heavy/0 uses a 4 MiB memory pool with AES-NI rounds.
cn_heavy_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_cn_heavy,
	name     = algo_name_cn_heavy,
	alias    = algo_alias_cn_heavy,
	memory   = 4 * 1024 * 1024,
	create   = cn_heavy_create,
	destroy  = cn_heavy_destroy,
	prepare  = cn_heavy_prepare,
	hash     = cn_heavy_hash,
}
