package frostrig_algo

import c "core:c"
import core "../core"
import ffi "../ffi"

algo_id_randomx_c64: core.Algo_Id = core.Algo_Id(4)
algo_name_randomx_c64: string = "rx/c64"
algo_alias_randomx_c64: string = "randomx-c64"

RandomX_C64_Context :: struct {
	ctx: ffi.RxC64_Context,
}

rxc64_make_flags :: proc(config: core.Algo_Config) -> c.int {
	f := ffi.rxc64_optimal_flags()
	if config.huge_pages {
		f |= c.int(1)
	}
	if config.full_memory {
		f |= c.int(4)
	}
	return f
}

rxc64_try_create :: proc(flags: c.int, key: []u8) -> (ctx: ffi.RxC64_Context, flags_used: c.int, err: core.Error) {
	ctx, err = ffi.rxc64_create(flags, key)
	if err != .None {
		lp := c.int(1)
		retry := flags & ~lp
		ctx, err = ffi.rxc64_create(retry, key)
		if err != .None {
			return {}, 0, err
		}
		return ctx, retry, .None
	}
	return ctx, flags, .None
}

rxc64_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	flags := rxc64_make_flags(config)
	key := config_key(config)
	ctx, flags_used, err := rxc64_try_create(flags, key[:])
	if err != .None {
		return {}, err
	}
	c := new(RandomX_C64_Context)
	c.ctx = ctx
	_ = flags_used
	return Algo_Handle{id = algo_id_randomx_c64, ctx = rawptr(c)}, .None
}

rxc64_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^RandomX_C64_Context) handle.ctx
	ffi.rxc64_destroy(c.ctx)
	free(c)
}

rxc64_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_C64_Context) handle.ctx
	return ffi.rxc64_prepare(c.ctx, seed)
}

rxc64_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_C64_Context) handle.ctx
	if ffi.RxC64_Context_Is_Nil(c.ctx) {
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
	err := ffi.rxc64_hash(c.ctx, buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

randomx_c64_entry: Algo_Entry = Algo_Entry{
	id     = algo_id_randomx_c64,
	name   = algo_name_randomx_c64,
	alias  = algo_alias_randomx_c64,
	memory = 2336 * 1024 * 1024,
	create = rxc64_create,
	destroy = rxc64_destroy,
	prepare = rxc64_prepare,
	hash   = rxc64_hash,
}
