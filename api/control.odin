package api

import "core:sync"

// Runtime_Control is the thread-safe hand-off between the API goroutine and
// the main mining loop.  The API writes new pool/miner values and raises
// `pending`; the main loop drains it once per second and reconnects/re-logs
// in.  All network I/O stays on the main goroutine.
Runtime_Control :: struct {
	mu:        sync.Mutex,
	pool_url:  string,
	miner_name: string,
	password:  string,
	pending:   bool,
}

// control_init seeds the control with the CLI-derived values.
control_init :: proc(c: ^Runtime_Control, pool_url, miner_name, password: string) {
	sync.lock(&c.mu)
	defer sync.unlock(&c.mu)
	c.pool_url = pool_url
	c.miner_name = miner_name
	c.password = password
	c.pending = false
}

// control_apply records a config update.  Empty fields are left unchanged
// (the API only sends the fields the caller wants to modify).
control_apply :: proc(c: ^Runtime_Control, pool_url, miner_name: string) {
	sync.lock(&c.mu)
	defer sync.unlock(&c.mu)
	if pool_url != "" {
		c.pool_url = pool_url
	}
	if miner_name != "" {
		c.miner_name = miner_name
	}
	c.pending = true
}

// control_consume drains a pending update exactly once.  It returns the latest
// desired values and whether a reconnect is required.  When there is no
// pending update it returns reconnect = false.
control_consume :: proc(c: ^Runtime_Control) -> (pool_url, miner_name, password: string, reconnect: bool) {
	sync.lock(&c.mu)
	defer sync.unlock(&c.mu)
	if !c.pending {
		return "", "", "", false
	}
	c.pending = false
	return c.pool_url, c.miner_name, c.password, true
}
