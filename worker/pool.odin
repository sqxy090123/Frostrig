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
	// stay valid for the thread lifetime). Each worker owns a disjoint nonce
	// segment: base = idx * STRIDE, so the shared cursor never races.
	mine_ctxs: [dynamic]mine_thread_ctx,
	// per-report baseline for computing H/s
	report_base:  u64,
	report_stamp: time.Time,
	// heap-aligned flag so atomic_load/atomic_store from threads is safe
	running: [dynamic]bool,
	// optional diagnostics (enabled by tests / main during bring-up)
	debug: bool,
	// live job feed: a stratum reader calls set_job_blob to publish a new
	// header; workers detect the bump via the atomic job_seq and re-seed
	// their stack-local blob copy.  blob_lock guards blob_dyn/blob so the
	// reader swap is not torn against a worker's per-window snapshot.
	job_seq:   [dynamic]u64,
	blob_lock: sync.Mutex,
}

// gui_trace_attach links a Worm/2 walk trace to worker 0's algorithm handle so
// the visualisation follows a single thread.  It reports false when the pool's
// algorithm has nothing to draw.
gui_trace_attach :: proc(pool: ^Pool, s: ^algo.Gui_State) -> bool {
	if pool == nil || s == nil || pool.count == 0 {
		return false
	}
	return algo.Attach_Worm2_Gui(pool.handles[0], s)
}

// gui_trace_detached leaves the handle untouched: the trace outlives a pool
// stop because stop() only destroys the contexts it owns.
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
// blob over a rolling nonce window so the user sees a real H/s figure while
// no stratum pool is connected.  Each worker owns a disjoint nonce segment
// (base = idx * STRIDE), so no field is shared-and-written across threads;
// only the atomic hash_count is shared.  Each completed slice bumps it.
mine_thread_ctx :: struct {
	pool:   ^Pool,
	idx:    u32,
	cursor: core.Nonce,
	// per-thread hash count, private to this worker.  The reporter sums the
	// contexts, so no global atomic counter is contended by N threads (which
	// would bounce a cache line on every window).
	hashes: u64,
}

// WINDOW hashes per slice.  A mid-size window keeps the H/s readout smooth
// for slow algorithms (RandomX: single hash is multi-ms, so a slice of 128
// is ~3s at typical rates and still ticks within the 5s report interval)
// while keeping the atomic hash_count update rate low enough that it is not
// a bottleneck for fast algorithms.
WINDOW :: 128

// STRIDE separates the nonce segments of two adjacent workers so their rolling
// windows can never collide for the first many slices.
STRIDE :: 1 << 20

// MAX_BLOB bounds the stack-local per-worker blob snapshot.  RandomX input is
// blob + 8-byte nonce and fits in 272 bytes; a 512-byte cap leaves room for
// larger headers while keeping the per-window copy trivially cheap.
MAX_BLOB :: 512

mine_loop :: proc(data: rawptr) {
	ctx := cast(^mine_thread_ctx) data
	p := ctx.pool
	idx := ctx.idx
	handle := p.handles[idx]
	if p.debug {
		fmt.printfln("[mine_loop] thread %v started (running=%v, pipeline=%v, handle.ctx=%v)",
			idx, sync.atomic_load(&p.running[0]), p.entry.pipeline != nil, handle.ctx != nil)
	}

	// Stack-local blob snapshot, refreshed only when the job_seq bumps.  This
	// keeps a consistent header for the whole window (no torn reads) and never
	// allocates on the hot path.
	local_buf: [MAX_BLOB]u8
	blob_len := 0
	last_seq: u64 = max(u64)
	blob := local_buf[:0]

	out := core.Hash{}
	base := core.Nonce(idx) * core.Nonce(STRIDE)

	for {
		if sync.atomic_load(&p.running[0]) == false {
			return
		}
		// refresh the blob snapshot if the pool published a new job
		seq := sync.atomic_load(&p.job_seq[0])
		if seq != last_seq {
			sync.lock(&p.blob_lock)
			blob_len = len(p.blob)
			if blob_len > MAX_BLOB {
				blob_len = MAX_BLOB
			}
			for i in 0 ..< blob_len {
				local_buf[i] = p.blob[i]
			}
			sync.unlock(&p.blob_lock)
			blob = local_buf[:blob_len]
			last_seq = seq
		}

		start := base + ctx.cursor
		// advance this thread's local cursor so the next slice is disjoint
		ctx.cursor = start + core.Nonce(WINDOW)

		if p.entry.pipeline != nil {
			_ = p.entry.pipeline(handle, blob, start, WINDOW)
		} else {
			for i in 0 ..< WINDOW {
				nonce := start + core.Nonce(i)
				_ = p.entry.hash(handle, blob, nonce, &out)
			}
		}
		// local counter: no shared atomic, no cache-line contention
		ctx.hashes += u64(WINDOW)
	}
}

// mine_common spawns one worker thread per configured thread and starts the
// hashing loop on the supplied blob slice (or a synthetic constant when blob
// is empty).  It is the stand-in for a real stratum job feed: it keeps the
// miner visibly busy and lets report() produce a meaningful H/s.  The blob
// bytes are copied into the pool's owned [dynamic]u8 so the workers' slice
// stays valid for the pool's lifetime.
mine_common :: proc(pool: ^Pool, blob: []u8) -> core.Error {
	if pool == nil {
		return .Invalid_Argument
	}
	if pool.state != .Running {
		return .Not_Initialized
	}

	if len(blob) == 0 {
		// synthetic 8-byte blob, same shape the pool would receive from a job
		pool.blob_dyn = make([dynamic]u8, 8)
		pool.blob_dyn[0] = 0xaa
		pool.blob_dyn[1] = 0x5a
	} else {
		pool.blob_dyn = make([dynamic]u8, len(blob))
		for i in 0 ..< len(blob) {
			pool.blob_dyn[i] = blob[i]
		}
	}
	pool.blob = pool.blob_dyn[:]

	pool.running = make([dynamic]bool, 1)
	pool.running[0] = true
	pool.job_seq = make([dynamic]u64, 1)
	pool.job_seq[0] = 0
	pool.report_base = 0
	pool.report_stamp = time.now()

	// per-thread context so each spawned thread knows its own index and
	// nonce segment
	pool.mine_ctxs = make([dynamic]mine_thread_ctx, pool.count)
	for i in 0 ..< pool.count {
		pool.mine_ctxs[i] = mine_thread_ctx{pool = pool, idx = u32(i), cursor = 0, hashes = 0}
	}

	for i in 0 ..< pool.count {
		pool.threads[i] = thread.create_and_start_with_data(rawptr(&pool.mine_ctxs[i]), mine_loop)
	}
	return .None
}

// mine starts the demo hashing loop on a synthetic blob (no pool connected).
mine :: proc(pool: ^Pool) -> core.Error {
	empty := make([]u8, 0)
	return mine_common(pool, empty)
}

// mine_with_blob behaves like mine() but seeds the workers from a real pool
// job blob instead of the synthetic constant.  Used by the --stratum path so
// the miner hashes the live job while the reader thread keeps the pool's
// job current for re-seeding.
mine_with_blob :: proc(pool: ^Pool, blob: []u8) -> core.Error {
	return mine_common(pool, blob)
}

// set_job_blob publishes a new job header to the workers.  It swaps the pool's
// owned blob buffer (freeing the old one) and bumps the atomic job_seq so the
// mining loops re-seed their stack-local snapshot on their next window.  Called
// by the stratum bridge (main) when the pool pushes a mining.set_job.
set_job_blob :: proc(pool: ^Pool, blob: []u8) {
	if pool == nil {
		return
	}
	sync.lock(&pool.blob_lock)
	old := pool.blob_dyn
	pool.blob_dyn = make([dynamic]u8, len(blob))
	for i in 0 ..< len(blob) {
		pool.blob_dyn[i] = blob[i]
	}
	pool.blob = pool.blob_dyn[:]
	sync.unlock(&pool.blob_lock)
	if len(old) > 0 {
		delete(old)
	}
	sync.atomic_add(&pool.job_seq[0], 1)
}

// report prints the H/s since the previous call and refreshes the baseline.
// It is meant to be invoked from the main loop every N seconds so the user
// sees live throughput without a pool.  The total is the sum of the per-thread
// private counters (no shared atomic is updated on the hot path).
report :: proc(pool: ^Pool, algo_name: string) {
	secs := time.duration_seconds(time.since(pool.report_stamp))
	if secs <= 0 {
		secs = 1
	}
	total := u64(0)
	for i in 0 ..< pool.count {
		total += sync.atomic_load(&pool.mine_ctxs[i].hashes)
	}
	hps := f64(total - pool.report_base) / f64(secs)
	pool.report_base = total
	pool.report_stamp = time.now()
	// keep the total readable as it climbs (millions+); show it in M units
	// once it passes a million hashes
	if total >= 1000000 {
		fmt.printfln("[H/s] %-8s threads=%v  %.0f H/s  (%.2fM total hashes)",
			algo_name, pool.count, hps, f64(total) / 1000000.0)
	} else {
		fmt.printfln("[H/s] %-8s threads=%v  %.0f H/s  (%v total hashes)",
			algo_name, pool.count, hps, total)
	}
}

// stop_mining signals the demo mining loops to halt, joins the threads, and
// leaves the handles intact so the caller can still destroy them via stop().
// It also frees the pool's owned dynamic buffers so a start/stop cycle does
// not leak them.
stop_mining :: proc(pool: ^Pool) {
	if pool == nil {
		return
	}
	if len(pool.running) > 0 {
		pool.running[0] = false
	}
	for i in 0 ..< pool.count {
		t := pool.threads[i]
		if t != nil {
			thread.join(t)
			thread.destroy(t)
			pool.threads[i] = nil
		}
	}
	// free the per-run dynamic buffers (blob owner, run flag, thread
	// contexts, job sequence).  They are re-created by the next mine_common
	// call.
	if len(pool.blob_dyn) > 0 {
		delete(pool.blob_dyn)
	}
	if len(pool.running) > 0 {
		delete(pool.running)
	}
	if len(pool.job_seq) > 0 {
		delete(pool.job_seq)
	}
	if len(pool.mine_ctxs) > 0 {
		delete(pool.mine_ctxs)
	}
	pool.blob = nil
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
