package frostrig_randomx_odin

import "core:mem"

DATASET_BASE_SIZE :: 2147483648
DATASET_EXTRA_SIZE :: 33554368
DATASET_SIZE :: DATASET_BASE_SIZE + DATASET_EXTRA_SIZE

// Odin_RandomX_Context owns every per-thread RandomX allocation: the Argon2
// derived cache, the ~2 GiB dataset and the interpreter VM with its
// 16-byte-aligned scratchpad.  A context is not reusable across dataset
// initialisations: call prepare once with the final key.
Odin_RandomX_Context :: struct {
	vm:      VM,
	cache:   Dataset_Cache,
	dataset: []u8,
	// sp_ptr keeps the raw scratchpad reservation address so destroy can give
	// it back; the VM only sees it as an aligned slice.
	sp_ptr: rawptr,
	ready:  bool,
}

create_odin_randomx :: proc() -> (ctx: ^Odin_RandomX_Context) {
	ctx = new(Odin_RandomX_Context)
	sp, _ := mem.alloc(SCRATCHPAD_SIZE, 16)
	ctx.sp_ptr = sp
	ctx.vm.scratchpad = ([^]u8)(sp)[:SCRATCHPAD_SIZE]
	return ctx
}

// prepare_odin_randomx rebuilds the Argon2 cache for `key` and then expands
// it into the full dataset.  Dataset expansion is sequential and is the
// dominant cost of a seed change; unlike the JIT build there is no way to
// overlap it with VM execution here.
prepare_odin_randomx :: proc(ctx: ^Odin_RandomX_Context, key: []u8) {
	ctx.cache = init_cache(key)
	ctx.dataset = make([]u8, DATASET_SIZE)
	n_items := DATASET_SIZE / CacheLineSize
	for it in 0 ..< n_items {
		init_dataset_item(&ctx.cache, ctx.dataset[it * CacheLineSize:][:CacheLineSize], u64(it))
	}
	ctx.vm.dataset = ctx.dataset
	ctx.ready = true
}

// hash_odin_randomx runs one RandomX hash over `input`, which must already be
// the complete RandomX input: the job blob followed by the 8-byte
// little-endian nonce.  It writes 32 bytes into `out`.  Callers build that
// concatenation themselves so that the common short-input case can stay on the
// stack instead of allocating per call.
hash_odin_randomx :: proc(
	ctx:   ^Odin_RandomX_Context,
	input: []u8,
	out:   []u8,
) {
	hash_main(&ctx.vm, input, out)
}

destroy_odin_randomx :: proc(ctx: ^Odin_RandomX_Context) {
	delete(ctx.dataset)
	if ctx.sp_ptr != nil {
		mem.free(ctx.sp_ptr)
	}
	free(ctx)
}