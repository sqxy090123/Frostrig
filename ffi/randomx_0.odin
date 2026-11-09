package frostrig_ffi

import core "../core"
import c "core:c"

// Rx0_Context is the opaque C handle returned by the "0" (default) RandomX
// variant module (algo/randomx/0.c).  All variant state lives inside the C
// context; the Odin side holds only this rawptr.
Rx0_Context :: distinct struct {
	_ptr: rawptr,
}

Rx0_Context_Is_Nil :: proc(ctx: Rx0_Context) -> bool {
	return ctx._ptr == nil
}

// rx0_optimal_flags returns the C-side recommended flags for the current
// machine (JIT + HARD_AES + ARGON2, auto-detected by the C module).
rx0_optimal_flags :: proc() -> c.int {
	return frostrig_rx0_optimal_flags()
}

// rx0_create initialises a RandomX variant-0 context.
// flags: c.int flag bitmask (use rx0_optimal_flags() as a starting point).
// key:   32-byte seed (block-height dependent in a real miner).
// Returns Rx0_Context and .None on success.
rx0_create :: proc(flags: c.int, key: []u8) -> (Rx0_Context, core.Error) {
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	p := frostrig_rx0_create(flags, key_ptr, key_size)
	if p == nil {
		return {}, .Ffi_Init_Failed
	}
	return Rx0_Context{_ptr = p}, .None
}

// rx0_destroy releases all resources owned by the C context.
rx0_destroy :: proc(ctx: Rx0_Context) {
	if ctx._ptr != nil {
		frostrig_rx0_destroy(ctx._ptr)
	}
}

// rx0_prepare (re)seeds the cache with a new key.  Call before each new job.
rx0_prepare :: proc(ctx: Rx0_Context, key: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	r := frostrig_rx0_prepare(ctx._ptr, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Init_Failed
	}
	return .None
}

// rx0_hash computes one RandomX hash.
// input: blob + nonce concatenated.
// output: receives 32 bytes.
rx0_hash :: proc(ctx: Rx0_Context, input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx0_hash(ctx._ptr, &input[0], c.size_t(len(input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// rx0_hash_first starts a pipelined multi-hash on the context.
rx0_hash_first :: proc(ctx: Rx0_Context, input: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return .Invalid_Argument
	}
	r := frostrig_rx0_hash_first(ctx._ptr, &input[0], c.size_t(len(input)))
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// rx0_hash_next outputs the previous hash and primes the next.
rx0_hash_next :: proc(ctx: Rx0_Context, next_input: []u8, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(next_input) == 0 || len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx0_hash_next(ctx._ptr, &next_input[0], c.size_t(len(next_input)), &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

// rx0_hash_last drains the final hash from the pipeline.
rx0_hash_last :: proc(ctx: Rx0_Context, output: []u8) -> core.Error {
	if ctx._ptr == nil {
		return .Ffi_Handle_Invalid
	}
	if len(output) < 32 {
		return .Invalid_Argument
	}
	r := frostrig_rx0_hash_last(ctx._ptr, &output[0])
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
