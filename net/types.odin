package frostrig_net

import core "../core"
import sync "core:sync"

Endpoint :: struct {
	host: string,
	port: u16,
}

Session_State :: enum u8 {
	Idle,
	Connecting,
	Connected,
	Logged_In,
	Closed,
}

// Job mirrors the active stratum mining job: when the pool pushes a
// mining.set_job the reader updates these fields and the worker mining loop
// re-seeds its blob from job_blob so it hashes against the real header.
Job_State :: struct {
	job_id:   core.Job_Id,
	blob:     [dynamic]u8, // current job header (owned)
	seed:     [dynamic]u8, // pool-provided seed (optional)
	seed_len: u32,
	// target as the hex string the pool sent, kept for share comparison /
	// difficulty display.  A leading "00..." means a high target.
	target_hex: string,
}

Session :: struct {
	endpoint: Endpoint,
	state:    Session_State,
	job_id:   core.Job_Id,

	// raw TCP socket handle (0 when not connected)
	socket: u32,

	// JSON-RPC credentials
	user: string,
	pass: string,

	// current job pushed by the pool
	job: Job_State,

	// read side: a reader goroutine appends newline-delimited JSON into
	// recv_buf and hands complete lines to handle_message().  The mutex
	// guards recv_buf and the socket so submit() can write concurrently.
	recv_buf:  [dynamic]u8,
	buf_lock:  sync.Mutex,
	// stop flag the reader checks; set by close()
	recv_stop: [dynamic]bool,

	// pool-reported difficulty, refreshed by mining.set_difficulty
	difficulty: f64,

	// stats
	accepted:  u64,
	rejected:  u64,
}
