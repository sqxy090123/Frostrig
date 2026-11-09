package frostrig_algo

import core "../core"

Algo_Handle :: struct {
	id:  core.Algo_Id,
	ctx: rawptr,
}

Algo_Create_Proc :: #type proc(config: core.Algo_Config) -> (handle: Algo_Handle, err: core.Error)
Algo_Destroy_Proc :: #type proc(handle: Algo_Handle)
Algo_Prepare_Proc :: #type proc(handle: Algo_Handle, seed: []u8) -> core.Error
Algo_Hash_Proc :: #type proc(
	handle: Algo_Handle,
	input: []u8,
	nonce: core.Nonce,
	output: ^core.Hash,
) -> core.Error

// Algo_Entry is one row of the registry.  `memory` is the approximate
// per-thread working-set size in bytes, used by the platform layer to
// pre-allocate huge pages before the pool starts.
Algo_Entry :: struct {
	id:      core.Algo_Id,
	name:    string,
	memory:  u64,
	create:  Algo_Create_Proc,
	destroy: Algo_Destroy_Proc,
	prepare: Algo_Prepare_Proc,
	hash:    Algo_Hash_Proc,
}
