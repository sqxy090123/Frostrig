package frostrig_algo

import c "core:c"
import core "../core"
import ffi "../ffi"

algo_id_randomx: core.Algo_Id = core.Algo_Id(1)

algo_name_randomx: string = "rx/0"
algo_alias_randomx: string = "randomx"

// RandomX_Context wraps the opaque C handle for the default RandomX variant.
// All per-thread state (cache, dataset, VM, scratchpad) lives inside the C
// context; the Odin side holds only this rawptr.
RandomX_Context :: struct {
	ctx:  ffi.Rx0_Context,
}

rx_make_flags :: proc(config: core.Algo_Config) -> c.int {
	f := ffi.rx0_optimal_flags()
	if config.huge_pages {
		f |= c.int(1)
	}
	if config.full_memory {
		f |= c.int(4)
	}
	return f
}

// config_key returns the 32-byte seed for the cache.  In a real miner the
// seed comes from the blockchain's block height; here we derive a stable
// placeholder from the config so the VM stays deterministic within a run.
config_key :: proc(config: core.Algo_Config) -> [dynamic]u8 {
	key := make([dynamic]u8, 32)
	key[0] = u8(config.thread_index & 0xff)
	key[1] = u8((config.flags >> 8) & 0xff)
	return key
}

// rx_try_create attempts to create a C context with the given flags.  If the
// context allocation fails (e.g. huge pages unavailable), it falls back to
// flags without the Large_Pages bit.
rx_try_create :: proc(flags: c.int, key: []u8) -> (ctx: ffi.Rx0_Context, flags_used: c.int, err: core.Error) {
	ctx, err = ffi.rx0_create(flags, key)
	if err != .None {
		lp := c.int(1)
		retry := flags & ~lp
		ctx, err = ffi.rx0_create(retry, key)
		if err != .None {
			return {}, 0, err
		}
		return ctx, retry, .None
	}
	return ctx, flags, .None
}

rx_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	flags := rx_make_flags(config)
	key := config_key(config)
	ctx, flags_used, err := rx_try_create(flags, key[:])
	if err != .None {
		return {}, err
	}
	c_ctx := new(RandomX_Context)
	c_ctx.ctx = ctx
	_ = flags_used
	return Algo_Handle{id = algo_id_randomx, ctx = rawptr(c_ctx)}, .None
}

rx_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	c_ctx := cast(^RandomX_Context) handle.ctx
	ffi.rx0_destroy(c_ctx.ctx)
	free(c_ctx)
}

// rx_prepare (re)initialises the cache with a new seed.
rx_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	c_ctx := cast(^RandomX_Context) handle.ctx
	return ffi.rx0_prepare(c_ctx.ctx, seed)
}

// rx_hash computes one RandomX hash.  The input is the concatenated
// blob + 8-byte little-endian nonce; output receives 32 bytes.
// Fast path: uses a stack buffer to avoid per-call heap allocation.
HASH_STACK_IN  :: 272
HASH_STACK_OUT :: 32

rx_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	c_ctx := cast(^RandomX_Context) handle.ctx
	if ffi.Rx0_Context_Is_Nil(c_ctx.ctx) {
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
		err := ffi.rx0_hash(c_ctx.ctx, buf[:len(input)+8], out[:])
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
	err := ffi.rx0_hash(c_ctx.ctx, d_buf[:], out[:])
	if err != .None {
		return err
	}
	for i in 0 ..< 32 {
		output.bytes[i] = out[i]
	}
	output.len = 32
	return .None
}

// to_le_bytes encodes a u64 nonce as 8 little-endian bytes.
to_le_bytes :: proc(v: u64) -> [8]u8 {
	b: [8]u8
	for i in 0 ..< 8 {
		b[i] = u8((v >> (u32(i) * 8)) & 0xff)
	}
	return b
}

// rx_pipeline hashes `count` sequential nonces (start_nonce .. start_nonce+count-1)
// against `input` in one C call.  It uses RandomX's first/next/last pipeline
// so the Argon2 cache-init of hash[i+1] overlaps the superscalar VM execution
// of hash[i]; the steady-state per-hash cost is lower than looping `rx_hash`.
// The final hash is drained and written to the last 32 bytes of the output
// buffer so the caller can verify or use it.  Total output size = count*32.
// Returns .None on success.
rx_pipeline :: proc(
	handle: Algo_Handle,
	input: []u8,
	start_nonce: core.Nonce,
	count: u64,
) -> core.Error {
	if handle.ctx == nil || count == 0 {
		return core.Error.Not_Initialized
	}
	c_ctx := cast(^RandomX_Context) handle.ctx
	if ffi.Rx0_Context_Is_Nil(c_ctx.ctx) {
		return core.Error.Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return core.Error.Invalid_Argument
	}

	// Allocate the output buffer once for the whole batch.
	outs := make([dynamic]u8, count * 32)
	// The C pipeline writes count-1 hashes and leaves the last pending; we
	// drain it into outs[(count-1)*32 ..] via rx0_hash_last below.
	err := ffi.rx0_hash_pipeline(c_ctx.ctx, input[:], u64(start_nonce), count, outs[:])
	if err != .None {
		return err
	}
	// Drain the final pending hash.
	last := outs[(count-1)*32:]
	err = ffi.rx0_hash_last(c_ctx.ctx, last[:])
	if err != .None {
		return err
	}
	// NOTE: the caller (worker) does not currently consume the per-hash outputs;
	// the value of benchmarking the pipeline is that the C call itself is faster.
	_ = outs
	return .None
}

// RandomX full-memory dataset is ~2336 MiB (2 GiB dataset + scratch).
// If allocation fails, the C module auto-falls back to light-mode cache
// (~2 MiB).
randomx_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_randomx,
	name     = algo_name_randomx,
	alias    = algo_alias_randomx,
	memory   = 2336 * 1024 * 1024,
	create   = rx_create,
	destroy  = rx_destroy,
	prepare  = rx_prepare,
	hash     = rx_hash,
	pipeline = rx_pipeline,
}
