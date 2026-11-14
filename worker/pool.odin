package frostrig_worker

import core "../core"
import algo "../algo"
import thread "core:thread"
import time "core:time"
import fmt "core:fmt"

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
