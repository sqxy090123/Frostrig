package frostrig_worker

import core "../core"
import algo "../algo"
import thread "core:thread"

MAX_WORKERS :: 256

Pool :: struct {
	config:  core.Miner_Config,
	threads: [MAX_WORKERS]^thread.Thread,
	count:   u32,
	queue:   Job_Queue,
	state:   core.Lifecycle,
	rest:    Rest_Window,
}

// mine_slice processes one nonce slice for the pool.  This is the hook
// point where a real mining backend (RandomX, SHA-3, etc.) will be
// called.  For now it is a placeholder that:
//   1. applies the developer fee to the slice (1% reserved for the
//      developer, the rest for the user),
//   2. ticks the rest window, and
//   3. if the rest window is due, calls rest_for to let the user's
//      machine take a break.
// The fee and rest are both placeholders; the actual hashing is left to
// the future algo backend.
mine_slice :: proc(pool: ^Pool, rng: Nonce_Range) -> core.Error {
	user_rng, dev_rng := apply_developer_fee(rng)
	// user_rng is what the user's machine works on; dev_rng is reserved
	// for the developer.  When a pool is integrated, dev_rng will be
	// directed to the developer's reward address.
	_ = user_rng
	_ = dev_rng

	if tick_rest_window(&pool.rest) {
		reset_rest_window(&pool.rest)
		rest_for()
	}
	return .None
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
	// Developer fee + rest window are initialised here so that when the
	// mining loop is wired up it already has a live Rest_Window to tick.
	// The fee itself is applied per nonce slice by
	// split_nonce_range_with_fee; the rest schedule is driven by
	// tick_rest_window + rest_for in fee.odin.
	pool.rest = Rest_Window{}
	pool.state = .Running
	return .None
}

stop :: proc(pool: ^Pool) -> core.Error {
	if pool == nil {
		return .Invalid_Argument
	}
	pool.state = .Stopping
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
