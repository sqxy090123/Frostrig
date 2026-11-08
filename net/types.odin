package frostrig_net

import core "../core"

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

Session :: struct {
	endpoint: Endpoint,
	state:    Session_State,
	job_id:   core.Job_Id,
}
