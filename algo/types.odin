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

//
// Pipeline: for algorithms that expose a first/next/last triple (RandomX,
// Keva), the registry may carry a batch proc that hashes `count` sequential
// nonces starting at `start_nonce` in one call.  The implementation is
// expected to use the algorithm's internal pipelined hashing (overlapping
// the Argon2 cache-init of hash[i+1] with the superscalar VM execution of
// hash[i]) so the steady-state cost per hash is lower than calling
// `hash` in a loop.  When nil, callers fall back to the plain `hash` loop.
//
Algo_Pipeline_Proc :: #type proc(
	handle: Algo_Handle,
	input: []u8,
	start_nonce: core.Nonce,
	count: u64,
) -> core.Error

// Algo_Entry is one row of the registry.  `memory` is the approximate
// per-thread working-set size in bytes, used by the platform layer to
// pre-allocate huge pages before the pool starts.  `alias` is an optional
// alternate name accepted by `lookup_by_name` (empty string = no alias).
// `pipeline` is optional; nil means the algorithm has no batched path and
// callers must loop `hash`.
Algo_Entry :: struct {
	id:       core.Algo_Id,
	name:     string,
	alias:    string,
	memory:   u64,
	create:   Algo_Create_Proc,
	destroy:  Algo_Destroy_Proc,
	prepare:  Algo_Prepare_Proc,
	hash:     Algo_Hash_Proc,
	pipeline:  Algo_Pipeline_Proc,
}
