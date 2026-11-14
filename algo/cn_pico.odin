package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_cn_pico: core.Algo_Id = core.Algo_Id(14)
algo_name_cn_pico: string = "cn-pico"
algo_alias_cn_pico: string = "cn_pico"

Cn_Pico_Context :: struct {
	ctx: ffi.Cn_Pico_Context,
}

cn_pico_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	ctx, err := ffi.cn_pico_create()
	if err != .None {
		return {}, err
	}
	c := new(Cn_Pico_Context)
	c.ctx = ctx
	return Algo_Handle{id = algo_id_cn_pico, ctx = rawptr(c)}, .None
}

cn_pico_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^Cn_Pico_Context) handle.ctx
	ffi.cn_pico_destroy(c.ctx)
	free(c)
}

cn_pico_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Cn_Pico_Context) handle.ctx
	return ffi.cn_pico_prepare(c.ctx, seed)
}

cn_pico_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^Cn_Pico_Context) handle.ctx
	if ffi.Cn_Pico_Context_Is_Nil(c.ctx) {
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
		err := ffi.cn_pico_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.cn_pico_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// CryptoNight Pico uses a 256 KiB memory pool.
cn_pico_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_cn_pico,
	name     = algo_name_cn_pico,
	alias    = algo_alias_cn_pico,
	memory   = 256 * 1024,
	create   = cn_pico_create,
	destroy  = cn_pico_destroy,
	prepare  = cn_pico_prepare,
	hash     = cn_pico_hash,
}
