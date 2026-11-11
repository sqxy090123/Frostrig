package frostrig_algo

import c "core:c"
import core "../core"
import ffi "../ffi"

algo_id_randomx_xeq: core.Algo_Id = core.Algo_Id(6)
algo_name_randomx_xeq: string = "rx/xeq"
algo_alias_randomx_xeq: string = "randomxeq"

RandomX_Xeq_Context :: struct {
	ctx: ffi.RxXeq_Context,
}

rxxeq_make_flags :: proc(config: core.Algo_Config) -> c.int {
	f := ffi.rxxeq_optimal_flags()
	if config.huge_pages {
		f |= c.int(1)
	}
	if config.full_memory {
		f |= c.int(4)
	}
	return f
}

rxxeq_try_create :: proc(flags: c.int, key: []u8) -> (ctx: ffi.RxXeq_Context, flags_used: c.int, err: core.Error) {
	ctx, err = ffi.rxxeq_create(flags, key)
	if err != .None {
		lp := c.int(1)
		retry := flags & ~lp
		ctx, err = ffi.rxxeq_create(retry, key)
		if err != .None {
			return {}, 0, err
		}
		return ctx, retry, .None
	}
	return ctx, flags, .None
}

rxxeq_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	flags := rxxeq_make_flags(config)
	key := config_key(config)
	ctx, flags_used, err := rxxeq_try_create(flags, key[:])
	if err != .None {
		return {}, err
	}
	c := new(RandomX_Xeq_Context)
	c.ctx = ctx
	_ = flags_used
	return Algo_Handle{id = algo_id_randomx_xeq, ctx = rawptr(c)}, .None
}

rxxeq_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^RandomX_Xeq_Context) handle.ctx
	ffi.rxxeq_destroy(c.ctx)
	free(c)
}

rxxeq_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_Xeq_Context) handle.ctx
	return ffi.rxxeq_prepare(c.ctx, seed)
}

rxxeq_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_Xeq_Context) handle.ctx
	if ffi.RxXeq_Context_Is_Nil(c.ctx) {
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
		err := ffi.rxxeq_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.rxxeq_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

randomx_xeq_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_randomx_xeq,
	name   = algo_name_randomx_xeq,
	alias  = algo_alias_randomx_xeq,
	memory = 2336 * 1024 * 1024,
	create = rxxeq_create,
	destroy = rxxeq_destroy,
	prepare = rxxeq_prepare,
	hash   = rxxeq_hash,
}
