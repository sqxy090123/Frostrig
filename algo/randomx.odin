package frostrig_algo

import core "../core"
import ffi "../ffi"

algo_id_randomx: core.Algo_Id = core.Algo_Id(1)

algo_name_randomx: string = "randomx"

// RandomX_Context holds the per-thread RandomX resources: a dedicated VM
// (with its own scratchpad) plus the shared cache and optional full
// dataset.  One context is created per worker thread; the cache and
// dataset are shared read-only across threads, so only the VM is
// per-thread.
RandomX_Context :: struct {
	cache:   ffi.Rx_Cache,
	dataset: ffi.Rx_Dataset,
	vm:      ffi.Rx_Vm,
	flags:   ffi.Rx_Flags,
}

rx_make_flags :: proc(config: core.Algo_Config) -> ffi.Rx_Flags {
	f: ffi.Rx_Flags = ffi.rx_get_optimal_flags()
	if config.huge_pages {
		f = ffi.rx_or(f, ffi.Rx_Flags(ffi.Rx_Flag.Large_Pages))
	}
	if config.full_memory {
		f = ffi.rx_or(f, ffi.Rx_Flags(ffi.Rx_Flag.Full_Mem))
	}
	if config.flags != 0 {
		f = ffi.rx_or(f, ffi.Rx_Flags(config.flags))
	}
	return f
}

// rx_try_create attempts to create a cache with the given flags.  If the
// cache allocation fails (e.g. huge pages unavailable), it falls back to
// flags without the Large_Pages bit.
rx_try_create :: proc(
	flags:  ffi.Rx_Flags,
	key:    []u8,
) -> (cache: ffi.Rx_Cache, flags_used: ffi.Rx_Flags, err: core.Error) {
	cache, err = ffi.rx_cache_create(flags, key)
	if err != .None {
		lp := u32(ffi.Rx_Flags(ffi.Rx_Flag.Large_Pages))
		retry := ffi.Rx_Flags(u32(flags) & ~lp)
		cache, err = ffi.rx_cache_create(retry, key)
		if err != .None {
			return {}, {}, err
		}
		return cache, retry, .None
	}
	return cache, flags, .None
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

rx_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	flags := rx_make_flags(config)
	key := config_key(config)

	cache, flags_used, err := rx_try_create(flags, key[:])
	if err != .None {
		return {}, err
	}

	dataset := ffi.Rx_Dataset{}
	if ffi.rx_has(flags_used, ffi.Rx_Flags(ffi.Rx_Flag.Full_Mem)) {
		dataset, err = ffi.rx_dataset_create(flags_used, cache)
		if err != .None {
			ffi.rx_cache_destroy(cache)
			return {}, err
		}
	}

	vm, vm_err := ffi.rx_vm_create(flags_used, cache, dataset)
	if vm_err != .None {
		err = vm_err
		if ffi.rx_dataset_is_nil(dataset) == false {
			ffi.rx_dataset_destroy(dataset)
		}
		ffi.rx_cache_destroy(cache)
		return {}, err
	}

	ctx := new(RandomX_Context)
	ctx.cache = cache
	ctx.dataset = dataset
	ctx.vm = vm
	ctx.flags = flags_used

	return Algo_Handle{id = algo_id_randomx, ctx = rawptr(ctx)}, .None
}

rx_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	ctx := cast_ptr(handle.ctx)
	ffi.rx_vm_destroy(ctx.vm)
	if ffi.rx_dataset_is_nil(ctx.dataset) == false {
		ffi.rx_dataset_destroy(ctx.dataset)
	}
	ffi.rx_cache_destroy(ctx.cache)
	free(ctx)
}

// rx_prepare (re)initialises the cache with a new seed.  In light-mode the
// cache is swapped into the live VM; in full-memory mode the dataset is
// reinitialised and swapped in.
rx_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	ctx := cast_ptr(handle.ctx)
	if len(seed) == 0 {
		return core.Error.Invalid_Argument
	}
	if ffi.rx_has(ctx.flags, ffi.Rx_Flags(ffi.Rx_Flag.Full_Mem)) {
		count := u64(ffi.randomx_dataset_item_count())
		ffi.randomx_init_dataset(
			ctx.dataset._ptr,
			ctx.cache._ptr,
			0,
			count,
		)
		return ffi.rx_vm_set_dataset(ctx.vm, ctx.dataset)
	}
	return ffi.rx_vm_set_cache(ctx.vm, ctx.cache)
}

// cast_ptr converts the opaque rawptr held in Algo_Handle.ctx back to a
// concrete ^RandomX_Context pointer.
cast_ptr :: proc(p: rawptr) -> ^RandomX_Context {
	return cast(^RandomX_Context) p
}

// rx_hash computes one RandomX hash.  The input is the concatenated
// blob + 8-byte little-endian nonce; output receives 32 bytes.
rx_hash :: proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	ctx := cast_ptr(handle.ctx)
	if ffi.rx_vm_is_nil(ctx.vm) {
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
	err := ffi.rx_vm_calculate(ctx.vm, buf[:], out[:])
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

// RandomX light-mode cache occupies 2 MiB.
randomx_entry: Algo_Entry = Algo_Entry{
	id = algo_id_randomx,
	name = algo_name_randomx,
	memory = 2 << 20,
	create = rx_create,
	destroy = rx_destroy,
	prepare = rx_prepare,
	hash = rx_hash,
}