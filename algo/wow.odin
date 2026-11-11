package frostrig_algo

import c "core:c"
import core "../core"
import ffi "../ffi"

algo_id_randomx_wow: core.Algo_Id = core.Algo_Id(2)

algo_name_randomx_wow: string = "rx/wow"
algo_alias_randomx_wow: string = "randomx-wow"

// RandomX_Wow_Context wraps the opaque C handle for the RandomX "wow"
// (V2) variant.  All per-thread state lives inside the C context.
RandomX_Wow_Context :: struct {
	ctx: ffi.RxWow_Context,
}

rxwow_make_flags :: proc(config: core.Algo_Config) -> c.int {
	f := ffi.rxwow_optimal_flags()
	if config.huge_pages {
		f |= c.int(1)
	}
	if config.full_memory {
		f |= c.int(4)
	}
	return f
}

rxwow_key :: proc(config: core.Algo_Config) -> [dynamic]u8 {
	key := make([dynamic]u8, 32)
	key[0] = u8(config.thread_index & 0xff)
	key[1] = u8((config.flags >> 8) & 0xff)
	return key
}

rxwow_try_create :: proc(flags: c.int, key: []u8) -> (ctx: ffi.RxWow_Context, flags_used: c.int, err: core.Error) {
	ctx, err = ffi.rxwow_create(flags, key)
	if err != .None {
		lp := c.int(1)
		retry := flags & ~lp
		ctx, err = ffi.rxwow_create(retry, key)
		if err != .None {
			return {}, 0, err
		}
		return ctx, retry, .None
	}
	return ctx, flags, .None
}

rxwow_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	flags := rxwow_make_flags(config)
	key := rxwow_key(config)
	ctx, flags_used, err := rxwow_try_create(flags, key[:])
	if err != .None {
		return {}, err
	}
	c := new(RandomX_Wow_Context)
	c.ctx = ctx
	_ = flags_used
	return Algo_Handle{id = algo_id_randomx_wow, ctx = rawptr(c)}, .None
}

rxwow_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c := cast(^RandomX_Wow_Context) handle.ctx
	ffi.rxwow_destroy(c.ctx)
	free(c)
}

rxwow_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_Wow_Context) handle.ctx
	return ffi.rxwow_prepare(c.ctx, seed)
}

rxwow_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c := cast(^RandomX_Wow_Context) handle.ctx
	if ffi.RxWow_Context_Is_Nil(c.ctx) {
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
		err := ffi.rxwow_hash(c.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.rxwow_hash(c.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// RandomX full-memory dataset is ~2336 MiB (2 GiB dataset + scratch).
// If allocation fails, the C module auto-falls back to light-mode cache
// (~2 MiB).
randomx_wow_entry: Algo_Entry = Algo_Entry{
	id    = algo_id_randomx_wow,
	name  = algo_name_randomx_wow,
	alias = algo_alias_randomx_wow,
	memory = 2336 * 1024 * 1024,
	create = rxwow_create,
	destroy = rxwow_destroy,
	prepare = rxwow_prepare,
	hash = rxwow_hash,
}
