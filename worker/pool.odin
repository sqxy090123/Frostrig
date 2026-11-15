package frostrig_worker

import core "../core"
import algo "../algo"
import thread "core:thread"
import time "core:time"
import fmt "core:fmt"
import sync "core:sync"

MAX_WORKERS :: 256

Pool :: struct {
	config:  core.Miner_Config,
	threads: [MAX_WORKERS]^thread.Thread,
	count:   u32,
	queue:   Job_Queue,
	state:   core.Lifecycle,
	rest:    Rest_Window,
	// per-thread algorithm handles, created in start() and destroyed in stop()
	handles: [MAX_WORKERS]algo.Algo_Handle,
	// cached entry resolved once in start(); avoids per-hash lookup
	entry:   algo.Algo_Entry,
	// shared blob for hashing (set by the mining loop once a job arrives)
	blob:    []u8,
	// owner of the blob backing array (roots the [dynamic]u8 so the blob
	// slice stays valid for the pool's lifetime)
	blob_dyn: [dynamic]u8,
	// per-thread mining contexts (rooted here so mine_loop's data pointers
	// stay valid for the thread lifetime)
	mine_ctxs: [dynamic]mine_thread_ctx,
	// rolling nonce cursor for the no-pool demo mining loop
	nonce_cursor: core.Nonce,
	// cumulative hashes since start (atomic; read by the reporter).  Kept as a
	// [dynamic]u64 so the counter lives in heap-aligned storage that the
	// atomic intrinsics can reliably update from multiple threads.
	hash_count: [dynamic]u64,
	// per-report baseline for computing H/s
	report_base:  u64,
	report_stamp: time.Time,
	// heap-aligned flag so atomic_load/atomic_store from threads is safe
	running: [dynamic]bool,
	// optional diagnostics (enabled by tests / main during bring-up)
	debug: bool,
}

// mine_slice processes one nonce slice for a specific worker thread.
// It applies the developer fee, ticks the rest window, and calls the
// algorithm hasher for each nonce in the user range.
mine_slice :: proc(pool: ^Pool, thread_idx: u32, rng: Nonce_Range) -> core.Error {
	user_rng, _ := apply_developer_fee(rng)

	if tick_rest_window(&pool.rest) {
		reset_rest_window(&pool.rest)
		rest_for()
	}

	blob := pool.blob
	out := core.Hash{}
	if pool.entry.pipeline != nil {
		// Batched pipeline path: hash the whole slice in one C call.
		_ = pool.entry.pipeline(pool.handles[thread_idx], blob,
			core.Nonce(user_rng.start), user_rng.count)
		return .None
	}
	for i in 0 ..< user_rng.count {
		nonce := core.Nonce(user_rng.start) + core.Nonce(i)
		_ = entry_hash(pool, thread_idx, blob, nonce, &out)
	}
	return .None
}

// entry_hash calls the cached algorithm's hash proc for one nonce.
entry_hash :: proc(pool: ^Pool, thread_idx: u32, blob: []u8, nonce: core.Nonce, out: ^core.Hash) -> bool {
	handle := pool.handles[thread_idx]
	err := pool.entry.hash(handle, blob, nonce, out)
	if err != .None {
		return false
	}
	return true
}

create :: proc(config: core.Miner_Config) -> (pool: Pool, err: core.Error) {
	if config.thread_count == 0 || config.thread_count > MAX_WORKERS {
		return {}, .Invalid_Argument
	}
	_, found := algo.lookup(config.algo)
	if !found {
		return {}, .Unsupported_Algo
	}
	pool.config = config
	pool.count = config.thread_count
	pool.state = .Created
	return pool, .None
}

start :: proc(pool: ^Pool) -> core.Error {
	if pool == nil {
		return .Invalid_Argument
	}
	if pool.state != .Created && pool.state != .Stopped {
		return .Already_Initialized
	}

	entry, ok := algo.lookup(pool.config.algo)
	if ok == false {
		return .Unsupported_Algo
	}
	pool.entry = entry

	// create one algo handle per worker thread
	for i in 0 ..< pool.count {
		cfg := core.Algo_Config{
			id           = pool.config.algo,
			huge_pages   = pool.config.huge_pages,
			full_memory  = false,
			flags        = 0,
			thread_index = u32(i),
		}
		handle, herr := entry.create(cfg)
		if herr != .None {
			// clean up already-created handles
			for j in 0 ..< i {
				entry.destroy(pool.handles[j])
			}
			return herr
		}
		pool.handles[i] = handle
	}

	pool.rest = Rest_Window{}
	pool.state = .Running
	return .None
}

stop :: proc(pool: ^Pool) -> core.Error {
	if pool == nil {
		return .Invalid_Argument
	}
	pool.state = .Stopping

	entry, ok := algo.lookup(pool.config.algo)
	if ok {
		for i in 0 ..< pool.count {
			if pool.handles[i].ctx != nil {
				entry.destroy(pool.handles[i])
				pool.handles[i] = algo.Algo_Handle{}
			}
		}
	}

	for i in 0 ..< pool.count {
		t := pool.threads[i]
		if t != nil {
			thread.join(t)
			thread.destroy(t)
			pool.threads[i] = nil
		}
	}
	pool.state = .Stopped
	return .None
}

// mine_loop is the per-thread worker for the no-pool demo loop. It hashes a
// synthetic blob over a rolling nonce window so the user sees a real H/s
// figure while no stratum pool is connected. Each completed slice bumps the
// shared atomic hash_count.
mine_thread_ctx :: struct {
	pool: ^Pool,
	idx:  u32,
}

mine_loop :: proc(data: rawptr) {
	ctx := cast(^mine_thread_ctx) data
	p := ctx.pool
	idx := ctx.idx
	handle := p.handles[idx]
	if p.debug {
		fmt.printfln("[mine_loop] thread %v started (running=%v, pipeline=%v, handle.ctx=%v)",
			idx, sync.atomic_load(&p.running[0]), p.entry.pipeline != nil, handle.ctx != nil)
	}

	blob := p.blob
	out := core.Hash{}
	// A small rolling window keeps the counter (and thus the H/s readout)
	// updating frequently.  RandomX is slow per hash, so a big window would
	// only tick once every many seconds; 8 hashes (~0.2s at typical rates)
	// gives a smooth figure while staying well below the bench cost.
	WINDOW :: 8

	for {
		if sync.atomic_load(&p.running[0]) == false {
			return
		}
		start := p.nonce_cursor
		// advance the cursor so the next slice is disjoint
		p.nonce_cursor = start + core.Nonce(WINDOW)

		if p.entry.pipeline != nil {
			_ = p.entry.pipeline(handle, blob, start, WINDOW)
		} else {
			for i in 0 ..< WINDOW {
				nonce := start + core.Nonce(i)
				_ = p.entry.hash(handle, blob, nonce, &out)
			}
		}
		sync.atomic_add(&p.hash_count[0], u64(WINDOW))
	}
}

// mine spawns one worker thread per configured thread and starts the demo
// hashing loop on a synthetic blob.  It is the no-pool stand-in for a real
// stratum job feed: it makes the miner visibly busy and lets report()
// produce a meaningful H/s.
mine :: proc(pool: ^Pool) -> core.Error {
	if pool == nil {
		return .Invalid_Argument
	}
	if pool.state != .Running {
		return .Not_Initialized
	}

	// synthetic 8-byte blob, same shape the pool would receive from a job
	pool.blob_dyn = make([dynamic]u8, 8)
	pool.blob_dyn[0] = 0xaa
	pool.blob_dyn[1] = 0x5a
	pool.blob = pool.blob_dyn[:]

	pool.running = make([dynamic]bool, 1)
	pool.running[0] = true
	pool.hash_count = make([dynamic]u64, 1)
	pool.nonce_cursor = 0
	pool.report_base = 0
	pool.report_stamp = time.now()

	// per-thread context so each spawned thread knows its own index
	pool.mine_ctxs = make([dynamic]mine_thread_ctx, pool.count)
	for i in 0 ..< pool.count {
		pool.mine_ctxs[i] = mine_thread_ctx{pool = pool, idx = u32(i)}
	}

	for i in 0 ..< pool.count {
		pool.threads[i] = thread.create_and_start_with_data(rawptr(&pool.mine_ctxs[i]), mine_loop)
	}
	return .None
}

// report prints the H/s since the previous call and refreshes the baseline.
// It is meant to be invoked from the main loop every N seconds so the user
// sees live throughput without a pool.
report :: proc(pool: ^Pool, algo_name: string) {
	if pool == nil {
		return
	}
	secs := time.duration_seconds(time.since(pool.report_stamp))
	if secs <= 0 {
		secs = 1
	}
	cur := sync.atomic_load(&pool.hash_count[0])
	hps := f64(cur - pool.report_base) / f64(secs)
	pool.report_base = cur
	pool.report_stamp = time.now()
	fmt.printfln("[H/s] %-8s threads=%v  %.0f H/s  (total %v hashes)",
		algo_name, pool.count, hps, cur)
}

// stop_mining signals the demo mining loops to halt, joins the threads, and
// leaves the handles intact so the caller can still destroy them via stop().
stop_mining :: proc(pool: ^Pool) {
	if pool == nil {
		return
	}
	pool.running[0] = false
	for i in 0 ..< pool.count {
		t := pool.threads[i]
		if t != nil {
			thread.join(t)
			thread.destroy(t)
			pool.threads[i] = nil
		}
	}
}

bench_args :: struct {
	entry:  algo.Algo_Entry,
	handle: algo.Algo_Handle,
	blob:   []u8,
	count:  u64,
}

bench_worker_data :: proc(data: rawptr) {
	a := cast(^bench_args) data
	// Prefer the pipeline batch path when the algorithm provides one:
	// one C call hashes `count` sequential nonces with the Argon2 cache-init
	// of hash[i+1] overlapping the VM execution of hash[i].  Falls back to
	// the per-hash loop when entry.pipeline is nil.
	if a.entry.pipeline != nil {
		_ = a.entry.pipeline(a.handle, a.blob, 0, a.count)
		return
	}
	out := core.Hash{}
	for i in 0 ..< a.count {
		_ = a.entry.hash(a.handle, a.blob, core.Nonce(i), &out)
	}
}

// benchmark runs a multi-threaded benchmark using the handles created by
// start().  Each thread hashes `count` nonces against a synthetic 8-byte
// blob; total throughput is printed in MH/s.
benchmark :: proc(pool: ^Pool, count: u64) {
	if pool == nil || count == 0 || pool.count == 0 {
		return
	}

	blob := make([dynamic]u8, 8)
	blob[0] = 0xaa

	args := make([dynamic]bench_args, pool.count)
	threads := make([dynamic]^thread.Thread, pool.count)
	for i in 0 ..< pool.count {
		args[i] = bench_args{
			entry  = pool.entry,
			handle = pool.handles[i],
			blob   = blob[:],
			count  = count,
		}
	}

	t0 := time.now()
	for i in 0 ..< pool.count {
		threads[i] = thread.create_and_start_with_data(rawptr(&args[i]), bench_worker_data)
	}
	for i in 0 ..< pool.count {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
	elapsed_ms := time.duration_milliseconds(time.since(t0))
	total_hashes := f64(pool.count) * f64(count)
	mhs := total_hashes / (elapsed_ms / 1000.0)
	fmt.printfln("benchmark: %v threads x %v hashes in %v ms  (%.1f H/s total)",
		u64(pool.count), count, u64(elapsed_ms+0.5), mhs)
}
