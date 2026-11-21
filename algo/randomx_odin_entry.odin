package frostrig_algo

import core "../core"

algo_id_randomx_odin: core.Algo_Id = core.Algo_Id(17)

algo_name_randomx_odin: string = "rx/odin"
algo_alias_randomx_odin: string = "randomx-odin"

// RANDOMX_HASH_SIZE
RX_ODIN_HASH_SIZE :: 32

// randomx_odin_entry routes the "rx/odin" id to the official RandomX JIT
// (librandomx.a) under Odin-layer management, sharing the same context,
// create/prepare/hash/pipeline machinery as rx/0.  The pure-Odin interpreter
// in algo/randomx_odin/ is kept as a self-hosted reference implementation and
// is exercised directly by the tests, but the entry itself no longer points at
// it: the entry now gets JIT speed instead of the ~6x-slower interpreter.
randomx_odin_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_randomx_odin,
	name     = algo_name_randomx_odin,
	alias    = algo_alias_randomx_odin,
	memory   = 2336 * 1024 * 1024,
	create   = rx_odin_create,
	destroy  = rx_destroy,
	prepare  = rx_prepare,
	hash     = rx_hash,
	pipeline = rx_pipeline,
}

rx_odin_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	return rx_create_for(algo_id_randomx_odin, config)
}
