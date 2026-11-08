package frostrig_core

Algo_Id   :: distinct u32
Job_Id    :: distinct u64
Worker_Id :: distinct u32
Nonce     :: u64

MAX_HASH_SIZE :: 64

Hash :: struct {
	bytes: [MAX_HASH_SIZE]u8,
	len:   u32,
}

Algo_Config :: struct {
	id:           Algo_Id,
	huge_pages:   bool,
	full_memory:  bool,
	flags:        u32,
	thread_index: u32,
}

Job :: struct {
	id:          Job_Id,
	algo:        Algo_Id,
	blob:        []u8,
	target:      Hash,
	seed:        []u8,
	nonce_start: Nonce,
	nonce_count: u64,
}

Share :: struct {
	job_id:    Job_Id,
	nonce:     Nonce,
	hash:      Hash,
	worker_id: Worker_Id,
}

Miner_Config :: struct {
	thread_count: u32,
	huge_pages:   bool,
	cpu_affinity: bool,
	algo:         Algo_Id,
}
